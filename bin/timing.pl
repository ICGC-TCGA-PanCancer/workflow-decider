use strict;
use DateTime;
use DateTime::Format::ISO8601;

# sudo apt-get install libdatetime-perl libdatetime-format-iso8601-perl

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

  foreach my $summary (glob("reports/$type/*/summary.tsv")) {
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

  foreach my $start (sort keys %{$d}) {
    foreach my $stop (sort keys %{$d->{$start}}) {
      print "$start\t$stop\t";
      print $d->{$start}{$stop};
      print "\n";
    }
  }
  my $avg = $t / $i;
  my $average_cost = $avg * $day_cost;
  print "AVG PER DONOR DAYS: $avg\n";
  print "AVG PER DONOR COST: \$$average_cost\n";
  print "TOTAL COST: \$$cost\n";

}
