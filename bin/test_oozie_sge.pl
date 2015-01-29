use strict;

# run this in the root cron
# */20 * * * * perl /root/test.pl > /root/test.log

my ($qjobs, $ojobs, $wjobs) = find_running();

my $tries = 10;
while ($qjobs == 0 && $ojobs > 0 && $wjobs > 0) {
  print "POTENTIAL PROBLEM\n";
  if ($tries <= 0) {
    print "ERROR: Restart Oozie '/etc/init.d/oozie restart'\n";
    my $result = system("/etc/init.d/oozie restart");
    if ($result != 0) { print "Problems with the restart\n"; }
    last;
  }
  sleep 60;
  ($qjobs, $ojobs, $wjobs) = find_running();
  $tries--;
}

sub find_running {

  my $qjobs = `sudo su -c 'qstat | wc -l' - seqware`;
  chomp $qjobs;

  my $ojobs = `sudo su -c 'oozie jobs | grep RUNNING | wc -l' - seqware`;
  chomp $ojobs;

  print "There are $qjobs SGE jobs running\n";
  print "There are $ojobs Oozie jobs running\n";

  my @accessions = split /\n/, `sudo su -c 'seqware workflow list | grep Accession | awk "{print \\\$4}"' - seqware`;

  print "Checking SeqWare Workflows\n";
  my $running_count = 0;
  foreach my $accession (@accessions) {
    chomp $accession;
    print "  Workflow accession $accession\n";
    my $running_workflows = `sudo su -c 'seqware workflow report --accession $accession | grep running | wc -l' - seqware`;
    chomp $running_workflows;
    print "    Running workflows $running_workflows\n";
    $running_count += $running_workflows;
  }

  print "The total running workflows $running_count\n";

  return($qjobs, $ojobs, $running_count);

}
