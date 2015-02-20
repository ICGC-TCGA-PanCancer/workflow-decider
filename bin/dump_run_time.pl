use strict;
use Statistics::Basic qw(:all);
use JSON;
die "USAGE $0 cluster.json" if (scalar(@ARGV) != 1);
my $cluster_info = $ARGV[0];
my %wf_time = ();
my %st_time = ();

my $json_txt = '';
if ($cluster_info ne "" && -e $cluster_info) {
    open IN, "<$cluster_info" or die "Can't open $cluster_info";
    while(<IN>) {
      $json_txt .= $_;
    }
    close IN;
    my $json = decode_json($json_txt);

    my $json_txt = `cat $ARGV[0]`;
    
    my $json = decode_json($json_txt);

      foreach my $c (keys %{$json}) {
           my $user = $json->{$c}{username};
           my $pass = $json->{$c}{password};
           my $web = $json->{$c}{webservice};
           my $acc = $json->{$c}{workflow_accession};
           my $max_running = $json->{$c}{max_workflows};
           my $max_scheduled_workflows = $json->{$c}{max_scheduled_workflows};

           my $str = `curl -u $user:$pass $web/reports/workflows/$acc`;
	   parseStr($str);
      }
}
strStats();

sub parseStr
{
    my $str = shift(@_);
    my @items = split("\t\tP",$str);
    for (my $i = 0; $i < @items; $i ++)
    {
        if ($items[$i] =~ /Run: (\S*)\s.*time: (\S*)\s/)
        {
            if (exists$wf_time{$1})
            {
                push(@{$wf_time{$1}},parseTime($2));
            }
            else
            {
                $wf_time{$1} = [];
                push(@{$wf_time{$1}},parseTime($2));
            }
        }

	if ($items[$i] =~ /ssing: (\S*)\s.*time: (\S*)\s/)
	{
	    if (exists $st_time{$1})
	    {
		push(@{$st_time{$1}},parseTime($2));
	    }
	    else
	    {
		$st_time{$1} = [];
		push(@{$st_time{$1}},parseTime($2));
	    }
	}
    }
}

sub strStats
{
    foreach my $type ("completed", "failed") {
	if (exists $wf_time{$type})
	{
            print uc "$type\n"; 
	    #print "Start\tStop\tDuration (days)\n";
   	    print "TOTAL DONORS:    \t".scalar(@{$wf_time{$type}})."\n";
	    my $mdn = median(@{$wf_time{$type}});
	    print "MEDIAN HOURS/DONOR:  \t$mdn\n";
	}
    }
print "\n\nProcessing Time by Steps:\n";
    foreach my $key (keys %st_time) {
        print "$key\n";
        my $mds = median(@{$st_time{$key}});
	print "MEDIAN HOURS/STEP:  \t $mds\n";
    }
}

sub parseTime
{
    my $str = shift @_;

    my @tmp = split(':', $str);
    my $h = $tmp[2]/3600 + $tmp[1]/60 + $tmp[0];#0:2:9.659
    return sprintf('%.3f', $h);
}
