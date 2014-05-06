use strict;
use Getopt::Long;
use Data::Dumper;
use JSON;
use Config;
$Config{useithreads} or die('Recompile Perl with threads to run this program.');
use threads;
use Storable 'dclone';

# PURPOSE:
# the program takes a command (use single quotes to encapsulate it in bash) and
# a comma-delimited list of files to check.  It also takes a retries count and
# cooldown time in seconds.  It then executes the command in a thread and
# watches the files every cooldown time.  For every period where there is no
# change in the output file sizes (one or more) then the retries count is
# decremented.  If there is a change then the retries count is reset the and
# process starts over.  If the retries are exhausted the thread is killed, the
# thread is recreated and started, and the process starts over.

my $command;
my @files;
# 30 retries at 60 seconds each is 0.5 hours
my $orig_retries = 30;
my $retries = $orig_retries;
# seconds
my $cooldown = 5;
# file size
my $previous_size = 0;

GetOptions (
  "command=s" => \$command,
  "files=s" => \@files,
);

print "FILES: ".join(' ', @files)."\n";

my $thr = threads->create(\&launch_and_monitor, $command);
while(1) {
  if ($thr->is_running()) {
    print "RUNNING\n";
    sleep $cooldown;
    if(getCurrentSize(@files) == $previous_size) {
      print "PREVIOUS SIZE UNCHANGED!!!\n";
      $retries--;
      if ($retries == 0) {
        $retries = $orig_retries;
        $thr->kill('KILL')->detach();
        $thr = threads->create(\&launch_and_monitor, $command);
        sleep $cooldown;
      }
    } else {
      print "SIZE INCREASED!!!\n";
      $previous_size = getCurrentSize(@files);
    }
  } else {
    print "DONE\n";
    # then we're done so just exit
    exit(0);
  }
}

sub launch_and_monitor {
  my ($cmd) = @_;
  system($cmd);
}

sub getCurrentSize {
  my @files = @_;
  my $size = 0;
  foreach my $file(@files) {
    foreach my $actual_file (find_file($file)) {
      print "CONSIDER: $actual_file\n";
      $size += -s $actual_file;
    }
  }
  return($size);
}

sub find_file {
  my ($file) = @_;
  my $output = `find . | grep $file`;
  my @a = split /\n/, $output;
  print join "\n", @a;
  return(@a);
}
