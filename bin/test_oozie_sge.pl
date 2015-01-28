use strict;

my ($qjobs, $ojobs, $wjobs) = find_running();

my $tries = 10;
while ($qjobs == 0 && $ojobs > 0 && $wjobs > 0) {
  print "POTENTIAL PROBLEM\n";
  if ($tries <= 0) {
    print "ERROR: Restart Oozie 'sudo /etc/init.d/oozie restart'\n";
    my $result = system("sudo /etc/init.d/oozie restart");
    if ($result != 0) { print "Problems with the restart\n"; }
    last;
  }
  sleep 60;
  ($qjobs, $ojobs, $wjobs) = find_running();
  $tries--;
}

sub find_running {

  my $qjobs = `qstat | wc -l`;
  chomp $qjobs;

  my $ojobs = `oozie jobs | grep RUNNING | wc -l`;
  chomp $ojobs;

  print "There are $qjobs SGE jobs running\n";
  print "There are $ojobs Oozie jobs running\n";

  my @accessions = split /\n/, `seqware workflow list | grep Accession | awk '{print \$4}'`;

  print "Checking SeqWare Workflows\n";
  my $running_count = 0;
  foreach my $accession (@accessions) {
    chomp $accession;
    print "  Workflow accession $accession\n";
    my $running_workflows = `seqware workflow report --accession $accession | grep running | wc -l`;
    chomp $running_workflows;
    print "    Running workflows $running_workflows\n";
    $running_count += $running_workflows;
  }

  print "The total running workflows $running_count\n";

  return($qjobs, $ojobs, $running_count);

}
