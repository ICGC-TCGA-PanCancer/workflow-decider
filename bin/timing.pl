use strict;
use DateTime;
use DateTime::Format::ISO8601;

# sudo apt-get install libdatetime-perl libdatetime-format-iso8601-perl

print "Start\tStop\tDuration (days)\n";

my $d = {};

foreach my $summary (glob("reports/completed/*/summary.tsv")) {
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
}

foreach my $start (sort keys %{$d}) {
  foreach my $stop (sort keys %{$d->{$start}}) {
    print "$start\t$stop\t";
    print $d->{$start}{$stop};
    print "\n";
  }
}
