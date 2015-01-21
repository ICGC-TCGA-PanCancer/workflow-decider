use strict;
use Data::Dumper;
use JSON;

local $/;

my ($dir) = @ARGV;

my @files = glob("$dir/data_*.xml");

my $total_files = 0;
my $total_bytes = 0;
my $total_runtime = 0;
my $total_download_time = 0;
my $total_specimens = 0;

foreach my $file (@files) {
  #print "FILE: $file\n";
  open IN, "<$file" or die;
  my $data = <IN>;
  close IN;
  if ($data =~ /Workflow_Bundle_BWA/ && $data =~ /aligned\+unaligned/) {
    #print "Match\n";
    $total_specimens++;
    my @l = split /\n/, $data;
    my $reading = 0;
    my $merge_time = 0;
    foreach my $_ (@l) {
      chomp;
      if (/<filename>/ && /\.bam/ && !/\.bam\.bai/) { #print "FILENAME: $_\n";
        $reading = 1; }
      if (/<filesize>(\d+)</ && $reading) { $reading = 0; $total_bytes += $1; $total_files++; }
      if (/<VALUE>({"timing\S+)<\/VALUE>/) {
         #print "$1\n"; 
         my $json = JSON->new->allow_nonref;
         my $perl_scalar = $json->decode( $1 );
         #print Dumper ($perl_scalar->{timing_metrics});
         foreach my $hash (@{$perl_scalar->{timing_metrics}}) {
            #print Dumper $hash->{metrics};
            $merge_time = $hash->{metrics}{merge_timing_seconds};
            $total_runtime += $hash->{metrics}{bwa_timing_seconds};
            $total_runtime += $hash->{metrics}{qc_timing_seconds};
            $total_runtime += $hash->{metrics}{download_timing_seconds};
            $total_download_time += $hash->{metrics}{download_timing_seconds};
          }
      }
    }
    $total_runtime += $merge_time;
  }
}

print "TOTAL FILES: $total_files\n";
print "TOTAL SPECIMENS: $total_specimens\n";
print "TOTAL BYTES: $total_bytes\n";
my $avg_gb = ($total_bytes / $total_files) / 1024 / 1024 / 1024;
print "AVG GB: $avg_gb\n";
print "TOTAL RUNTIME: $total_runtime\n";
print "TOTAL DOWNLOAD TIME: $total_download_time\n";
my $avg_runtime = ($total_runtime / $total_specimens) / 3600;
my $avg_runtime_down = ($total_download_time / $total_specimens) / 3600;
print "AVG RUNTIME HOURS: $avg_runtime\n";
print "AVG DOWNLOAD RUNTIME HOURS: $avg_runtime_down\n";

$total_files = 0;
$total_bytes = 0;
$total_runtime = 0;
$total_download_time = 0;
$total_specimens = 0;

foreach my $file (@files) {
  #print "FILE: $file\n";
  open IN, "<$file" or die;
  my $data = <IN>;
  close IN;
  if ($data =~ /SangerPancancerCgpCnIndelSnvStr/) {
    #print "Match\n";
    $total_specimens++;
    my @l = split /\n/, $data;
    my $reading = 0;
    my $merge_time = 0;
    foreach my $_ (@l) {
      chomp;
      if (/<filename>/) { #print "FILENAME: $_\n";
        $reading = 1; }
      if (/<filesize>(\d+)</ && $reading) { $reading = 0; $total_bytes += $1; $total_files++; }
    }
  }
}

print "TOTAL FILES: $total_files\n";
print "TOTAL SPECIMENS: $total_specimens\n";
print "TOTAL BYTES: $total_bytes\n";
my $avg_gb = ($total_bytes / $total_specimens) / 1024 / 1024 / 1024;
print "AVG GB: $avg_gb\n";


