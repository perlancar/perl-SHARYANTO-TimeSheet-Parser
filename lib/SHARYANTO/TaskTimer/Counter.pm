package SHARYANTO::TaskTimer::Counter;

use 5.010001;
use strict;
use warnings;

use Perinci::Sub::Util qw(err);

# VERSION

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(calc_hours_minutes fill_in_daily_totals total_daily_totals);

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
            return [400, "Unknown duration specification '$_'"];
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

    [200, "OK", sprintf "+%02d:%02d", $h, $m];
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
    [200, "OK", join("", @entries)];
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
    my $str = $args{str} or return [400, "Please specify str"];

    # per-activity-type- & per-project breakdowns
    my (%activities, %projects);

        # XXX schema
    for (qw/min_date max_date/) {
        return [400, "Invalid value for $_, please use YYYY-MM-DD"]
            if defined($args{$_}) && $args{$_} !~ /\A\d{4}-\d\d-\d\d\z/;
    }

    my @p;
    for my $l (split /^/, $str) {
        next unless $l =~ /\A\* \[(\d{4}-\d{2}-\d{2}) [^\]]*\] \((\+\d\d:\d{2})\)/;
        next if $args{min_date} && $1 lt $args{min_date};
        next if $args{max_date} && $1 gt $args{max_date};
        push @p, $2;
    }
    my $res = calc_hours_minutes(str => join(" ", @p));
    return err($res) unless $res->[0] == 200;
    [200, "OK", join("", $res->[2])];
}

1;
# ABSTRACT: Count periods

=head1 SYNOPSIS

Format of my timesheet-daily.org:

 * [2013-04-05 Fri] (+02:05) priv-notes, priv-finance
 - 07:36-08:25 -00:10 = +00:41 = (notes) priv-notes, priv-finance: nyicil utang
 - 08:48-09:27 = +00:39 = (coding) pericmd: debug why default format recently no
   longer text-pretty (e.g. list-id-holidays or list-id-holidays --detail)
 - 14:54-15:15 = +00:19 = (design) ansitable: desain fitur2x
 - 15:39-16:55 = +01:16 = (coding) dux: bool

The first line will contain the total hours and minutes for that day.

=cut
