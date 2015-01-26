use strict;
use JSON;
use Data::Dumper;
use DateTime;
use DateTime::Format::ISO8601;

# perl bin/make_trajectory_plot.pl donor_p_150120030101.jsonl
# wget http://pancancer.info/gnos_metadata/latest/donor_p_150120030101.jsonl.gz

my ($file) = @ARGV;

my $counts = {};

my $json = JSON->new->allow_nonref;

open IN, "<$file" or die;
while(<IN>) {
  chomp;
  my $d = $json->decode($_);
  if ($_ =~ /\.vcf/) {
    #print Dumper($d); die;
    #print Dumper($d->{'variant_calling_results'}{'sanger_variant_calling'}{'gnos_last_modified'});
    my $date_str = $d->{'variant_calling_results'}{'sanger_variant_calling'}{'gnos_last_modified'}[0];
    print "DATE: $date_str\n";
    my $date = DateTime::Format::ISO8601->parse_datetime($date_str);
    my $year = $date->year();
    my $month = $date->month();
    my $day = $date->day();
    if (length($month) < 2) { $month = "0$month"; }
    if (length($day) < 2) { $day = "0$day"; }
    #print "  $year $month $day\n";
    $counts->{"$year\-$month\-$day"}++;
  }
}
close IN;

my $cumulative = 0;
foreach my $str (sort keys %{$counts}) {
  my @d = split /\-/, $str;
  $cumulative += $counts->{$str};
  my $year = $d[0];
  $year =~ s/20//;
  print "$d[1]-$d[2]-$year\t".$counts->{$str}."\t$cumulative\n";
}

#print Dumper($counts);
