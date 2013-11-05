package SHARYANTO::TimeSheet::Parser;

use 5.010001;
use strict;
use warnings;

#use List::Util qw(sum);
use Perinci::Sub::Util qw(err);

# VERSION

# i currently don't like periexp because it brings in wrapping (and thus dsah
# etc), i don't like the slight overhead.

#use Perinci::Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(
                       calc_hours_minutes fill_in_daily_totals
                       parse_daily_sheet total_daily_totals
               );

our %SPEC;

$SPEC{calc_hours_minutes} = {
    v => 1.1,
    args => {
        str => {
            summary => 'durations specification',
            schema => 'str*',
            req => 0,
            pos => 0,
            description => <<'_',

Example:

    08:30-10:10 +02:00 -01:00

will result in: +02:40

_
        },
    },
    result_naked => 1,
};
sub calc_hours_minutes {
    my (%args) = @_;
    my $str = $args{str};

    my ($h, $m);

    for (split /\s+/, $str) {
        #say "part=$_";
        if (/^\+(\d{2,6}):(\d\d)$/) {
            $h += $1;
            $m += $2;
        } elsif (/^-(\d{2,6}):(\d\d)$/) {
            $h -= $1;
            $m -= $2;
        } elsif (my ($h1,$m1,$h2,$m2) = /^(\d{2,6}):(\d\d)-(\d{2,6}):(\d\d)$/) {
            if ($h2 < $h1 || $h2 <= $h1 && $m2 <= $m1) {
                $h2 += 24;
            }
            $h += ($h2-$h1);
            $m += ($m2-$m1);
        } else {
            die "Unknown duration specification '$_'";
        }
        #say "h=$h, m=$m";
    }

    while ($m < 0) {
        $h--;
        $m += 60;
    }
    while ($m >= 60) {
        $h++;
        $m -= 60;
    }

    sprintf "+%02d:%02d", $h, $m;
}

sub _dur2mins {
    my $dur = shift;
    $dur =~ /(\d+):(\d+)/ or return 0;
    $1*60 + $2;
}

sub _mins2dur {
    my $mins = shift;
    my $hours = int($mins/60);
    $mins -= $hours*60;
    sprintf("+%02d:%02d", $hours, $mins);
}

$SPEC{fill_in_daily_totals} = {
    v => 1.1,
    summary => 'Fill-in daily totals',
    description => <<'_',

Given something like this:

    * [2013-04-05 Fri] () blah
      - +01:10 = (coding) blah 1
      - +02:00 = (coding) blah 2
    * [2013-04-04 Thu] () blah
      - 09:00-10:30 = (coding) blah
      - +03:00 = (writing) blog: perl: hacktivity report & distribution-
        oriented development

will return the entries with daily totals filled in:

    * [2013-04-05 Fri] (+03:10) blah
      - +01:10 = (coding) blah 1
      - +02:00 = (coding) blah 2
    * [2013-04-04 Thu] (+04:45) blah
      - 09:00-10:45 = (coding) blah
      - +03:00 = (writing) blog: perl: hacktivity report & distribution-
        oriented development

Will check daily total if already set.

_
    args => {
        str => {
            summary => 'Text containing one or more daily entries.',
            schema  => 'str*',
            pos     => 0,
            req     => 1,
            cmdline_src => 'stdin_or_files',
        },
    },
    result_naked => 1,
};
sub fill_in_daily_totals {
    my %args = @_;
    my $str = $args{str} or return [400, "Please specify str"];

    my @entries = split /^(?=\* )/m, $str;

    for my $e (@entries) {
        my ($date, $total) =
            $e =~ /\A\* \[(\d{4}-\d{2}-\d{2}) [^\]]*\] \((\+\d\d:\d{2})?\)/
                or return [400, "Invalid daily header in '$e'"];
        my @p;
        for (split /^/, $e) {
            if (/^- (?:.+?) = (\+\d\d:\d\d) = /) {
                # line like: - 07:36-08:25 -00:10 = +00:41 = (notes) ...
                push @p, $1;
            } elsif (/^- (.+?) = /) {
                #  line like: - 17:05-19:25 -00:10 = (coding) ...
                push @p, $1;
            } else {
                # ignore other lines
            }
        }
        my $res = calc_hours_minutes(str => join(" ", @p));
        return err($res) unless $res->[0] == 200;
        my $ctotal = $res->[2];
        if ($total) {
            return [409, "Wrong daily totals for '$e' (should've been $ctotal)"]
                unless $total eq $ctotal;
        } else {
            $e =~ s/\(\)/($ctotal)/;
        }
    }
    join "", @entries;
}

$SPEC{parse_daily_sheet} = {
    v => 1.1,
    summary => 'Parse daily timesheet document',
    args => {
        str => {
            summary => 'Text containing the document',
            schema  => 'str*',
            pos     => 0,
            req     => 1,
            cmdline_src => 'stdin_or_files',
        },
        min_date => {
            summary => 'Only include entries with date not earlier than this',
            schema  => 'str*', # XXX date
            tags    => ['category:filtering'],
        },
        max_date => {
            summary => 'Only include entries with date not later than this',
            schema  => 'str*', # XXX date
            tags    => ['category:filtering'],
        },
    },
    result_naked => 1,
};
sub parse_daily_sheet {
    my %args = @_;

    # XXX schema
    defined($args{str}) or return [400, "Please specify str"];
    for (qw/min_date max_date/) {
        return [400, "Invalid value for $_, please use YYYY-MM-DD"]
            if defined($args{$_}) && $args{$_} !~ /\A\d{4}-\d\d-\d\d\z/;
    }

    my @entries;
    my $i = 0;
    for my $entry0 (split /^\* /m, $args{str}) {
        next unless $entry0 =~ /\S/;
        $i++;
        my ($date, $dets0) =
            $entry0 =~ /\A\[(\d{4}-\d\d-\d\d)[^\]]*\][^\n]*\n(.+)/s
                or die "Invalid entry (#$i): $entry0";
        next if $args{min_date} && $date lt $args{min_date};
        next if $args{max_date} && $date gt $args{max_date};
        my $entry = {date => $date, details=>[]};
        my $j = 0;
        for my $det (split /^- /ms, $dets0) {
            next unless $det =~ /\S/;
            $j++;
            $det =~ s/\n/ /g;
            $det =~ s/\s{2,}/ /g;
            my ($dur0, $act, $projs, $desc) =
                $det =~ /\A(.+?)\s*=\s*
                         \(([\w-]+)\)\s*
                         ([\w-]+(?:\s*,\s*[\w-]+)*)\s*
                         (?::\s*(.+))?/xs
                    or die "Invalid detail #$j on entry #$i: $det";
            $desc =~ s/\s+\z//s if defined $desc;
            my $dur = calc_hours_minutes(str => $dur0);
            push @{ $entry->{details} }, {
                raw          => $det,
                raw_duration => $dur0,
                duration     => $dur,
                minutes      => _dur2mins($dur),
                activity     => $act,
                projects     => [split /\s*,\s*/, $projs],
                description  => $desc,
            };
        }
        push @entries, $entry;
    }

    \@entries;
}

$SPEC{total_daily_totals} = {
    v => 1.1,
    summary => 'Total daily totals',
    args => {
        str => {
            summary => 'Text containing one or more daily entries.',
            schema  => 'str*',
            pos     => 0,
            req     => 1,
            cmdline_src => 'stdin_or_files',
        },
        min_date => {
            summary => 'Only include entries with date not earlier than this',
            schema  => 'str*', # XXX date
            tags    => ['category:filtering'],
        },
        max_date => {
            summary => 'Only include entries with date not later than this',
            schema  => 'str*', # XXX date
            tags    => ['category:filtering'],
        },
    },
};
sub total_daily_totals {
    my %args = @_;
    defined($args{str}) or return [400, "Please specify str"];

    my $entries = parse_daily_sheet(
        str => $args{str},
        ( min_date=>$args{min_date} ) x !!defined($args{min_date}),
        ( max_date=>$args{max_date} ) x !!defined($args{max_date}),
    );

    my %activity_mins;
    my %project_mins;
    my $totmins = 0;
    for my $e (@$entries) {
        for my $d (@{ $e->{details} }) {
            $totmins += $d->{minutes};
            $activity_mins{$d->{activity}} += $d->{minutes};
            my $n = @{ $d->{projects} };
            for (@{ $d->{projects} }) {
                $project_mins{$_} += $d->{minutes} / $n;
            }
        }
    }

    my %activity_durs;
    my %project_durs;
    my %activity_durpcts;
    my %project_durpcts;

    for (keys %activity_mins) {
        $activity_durpcts{$_} = $activity_mins{$_}/$totmins*100;
        $activity_durs{$_}    = _mins2dur($activity_mins{$_});
    }
    for (keys %project_mins ) {
        $project_durpcts{$_}  = $project_mins{$_}/$totmins*100;
        $project_durs{$_}     = _mins2dur($project_mins{$_});
    }

    [200, "OK", join("", _mins2dur($totmins)), {
        "func.breakdowns" => {
            activity_minutes   => \%activity_mins,
            project_minutes    => \%project_mins,
            activity_durations => \%activity_durs,
            project_durations  => \%project_durs,
            activity_durpcts   => \%activity_durpcts,
            project_durpcts    => \%project_durpcts,
        },
    }];
}

1;
# ABSTRACT: Parse my timesheet documents

=head1 SYNOPSIS


=head1 DESCRIPTION

Below is how I track my working times.

I use five Org files: C<timesheet-daily.org> (symlinked to C<daily.org> for
convenience), C<timesheet-weekly.org> (C<weekly.org>), C<timesheet-monthly.org>
(C<monthly.org>), C<timesheet-quarterly.org> (C<quarterly.org>), and
C<timesheet-yearly.org> (C<yearly.org>).

I still find it more flexible to manually jot down clocks or dudations (typing
C<hh:mm-hh:mm> or C<+hh:mm> or C<-hh:mm>) in C<daily.org> because I sometimes
intersperse different projects or take breaks. Then there is this module to
parse the C<daily.org> and total the durations to C<weekly.org> and so on.

The format of C<daily.org> (hopefully quite evident from example):

 * [2013-04-05 Fri] (+02:05)
 - 07:36-08:25 -00:10 = +00:41 = (notes) priv-notes, priv-finance: nyicil utang
 - 08:48-09:27 = +00:39 = (coding) pericmd: debug why default format recently no
   longer text-pretty (e.g. list-id-holidays or list-id-holidays --detail)
 - 14:54-15:15 = +00:19 = (design) ansitable: desain fitur2x
 - 15:39-16:55 = +01:16 = (coding) dux: bool

Each heading signifies a day. The heading contains a timestamp and a total
working duration for that day (can be calculated using C<fill_in_daily_totals()>
or through L<fill-in-daily-totals> script, I use Emacs and copy-paste to/from
C<daily.org> and shell buffer). Inside the heading, there's a list containing
duration for each task. The word after the equal sign and inside parentheses is
called the task/activity type. After that comes the project name(s) followed by
colon. After that comes detailed description.

Format of C<weekly.org> (by example):

 XXX


=head1 SEE ALSO

L<SHARYANTO>

=cut
