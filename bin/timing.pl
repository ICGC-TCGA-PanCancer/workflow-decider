use strict;
use DateTime;
use DateTime::Format::ISO8601;
use Statistics::Basic qw(:all);
use List::Util qw< min max >;

# INSTALL:
# sudo apt-get install libdatetime-perl libdatetime-format-iso8601-perl libstatistics-basic-perl

die "USAGE $0 <report_dir>" if (scalar(@ARGV) != 1);

my ($report_dir) = @ARGV;

foreach my $type ("completed", "failed") {

  print uc "$type\n";
  print "Start\tStop\tDuration (days)\n";

  my $d = {};

  my $i = 0;
  my $t = 0;
  my $cost = 0;

  # burn rate
  # 1024 TB
  my $ebs_per_day = 120 / 30;
  # 20GB upload
  my $gb_out_20 = 2;
  # 0.40 * 24
  my $rc_8xlarge_per_day = 10;
  my $day_cost = $ebs_per_day + $gb_out_20 + $rc_8xlarge_per_day;

  foreach my $summary (glob("$report_dir/$type/*/summary.tsv")) {
    #print "$summary\n";
    my $txt = `cat $summary`;
    #print "$txt\n";
    #print "\n\n";
    my $start;
    my $stop;
    $txt =~ /updateTimestamp\s+(\S+)\s*/i;
    $stop = $1;
    $txt =~ /createTimestamp\s+(\S+)\s*/i;
    $start = $1;
    #print "start: $start stop: $stop\n";
    my $dtstart = DateTime::Format::ISO8601->parse_datetime($start);
    my $dtstop = DateTime::Format::ISO8601->parse_datetime($stop);
    my $diff = $dtstop->subtract_datetime_absolute($dtstart);
    #print "DIFF: ".$diff->seconds()."\n";
    my $hours = ($diff->seconds() / 60) /60;
    #print "DIFF HOURS: $hours\n";
    my $days = $hours / 24;
    $d->{$start}{$stop} = $days;
    $i++;
    $t += $days;
    $cost += ($days * $day_cost);
  }

  my @days;

  foreach my $start (sort keys %{$d}) {
    foreach my $stop (sort keys %{$d->{$start}}) {
      print "$start\t$stop\t";
      print $d->{$start}{$stop};
      print "\n";
      push @days, $d->{$start}{$stop};
    }
  }
  my $avg = $t / $i;
  my $average_cost = $avg * $day_cost;
  print "TOTAL DONORS:\t".scalar(@days)."\n";
  print "AVG DAYS/DONOR:\t$avg\n";
  my $hours = 24*$avg;
  print "AVG HOURS/DONOR:\t$hours\n";

  my $median = median(@days);
  my $stddev = stddev(@days);
  my $min = min @days;
  my $max = max @days;

  print "MEDIAN DAYS/DONOR:\t$median\n";
  $hours = $median * 24;
  print "MEDIAN HOURS/DONOR:\t$median\n";
  print "STDDEV DAYS/DONOR:\t$stddev\n";
  $hours = $stddev * 24;
  print "STDDEV DAYS/DONOR:\t$hours\n";
  print "MIN DAYS:\t$min\n";
  $hours = $min * 24;
  print "MIN HOURS:\t$min\n";
  print "MAX DAYS:\t$max\n";
  $hours = $max * 24;
  print "MAX HOURS:\t$hours\n";
  print "AVG COST/DONOR:\t\$$average_cost\n";
  print "TOTAL APPROX COST:\t\$$cost\n";

}
