package SeqWare::Cluster;

use strict;
use warnings;
use feature qw(say);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use IPC::System::Simple;
use autodie qw(:all);
use Carp::Always;

use File::Slurp;

use XML::DOM;
use JSON;
use XML::LibXML;
use XML::Simple;
use Config::Simple;

use Data::Dumper;

sub combine_local_data {
    my ($self, $running_sample_ids, $failed_samples, $completed_samples, $local_cache_file, $sample_info) = @_;

    my $analysis_id_to_donor = parse_donors($sample_info);

    print Dumper $running_sample_ids;
    print Dumper $failed_samples;
    print Dumper $completed_samples;
    print Dumper $sample_info;

    # a hash that stores decider run counts since last seen for a previously running sample
    my $count_since_last_seen = {};

    # used for lost
    my $lost_samples = {};

    # $samples_status->{$run_status}{$mergedSortedIds}{$created_timestamp}{$sample_id} = $run_status;
    # read it if it exists and add to structure
    if (-e $local_cache_file && -s $local_cache_file > 0) {
        open my $in, '<', $local_cache_file;
        while(<$in>) {
            chomp;
            next if (/^#/);
            my @a = split /\t/;
            if ($a[3] eq 'running') {
              # keeping a count so eventually can declare these "lost" and retry them
              if (defined($running_sample_ids->{$a[0]}{$a[1]}{$a[2]})) {
                $count_since_last_seen->{$a[0]}{$a[1]}{$a[2]} = 0;
              } else {
                $count_since_last_seen->{$a[0]}{$a[1]}{$a[2]} = $a[6] + 1;
                # TODO: make this a configurable option
                if ($count_since_last_seen->{$a[0]}{$a[1]}{$a[2]} > 5) {
                  $lost_samples->{$a[0]}{$a[1]}{$a[2]} = 'lost'; 
                }
                else { $running_sample_ids->{$a[0]}{$a[1]}{$a[2]} = $a[3]; }
              }
            }
            elsif ($a[3] eq 'completed') {
                $completed_samples->{$a[0]}{$a[1]}{$a[2]} = $a[3];
            }
            elsif ($a[3] eq 'failed') {
              $failed_samples->{$a[0]}{$a[1]}{$a[2]} = $a[3];
            }
            elsif ($a[3] eq 'lost') {
              $lost_samples->{$a[0]}{$a[1]}{$a[2]} = $a[3];
            }
            else {
                # just add to failed if don't know
                $failed_samples->{$a[0]}{$a[1]}{$a[2]} = $a[3];
            }
        }
        close $in;
    }
    # now save these back out, running is always a fresh list of what's really running
    open my $out, '>', $local_cache_file;
    say $out "#MergedSortedAnalysisIds\tCreateTimestamp\tSampleId\tState\tProject\tDonorId\tCountsSinceLastSeen";
    foreach my $hash ($running_sample_ids, $failed_samples, $completed_samples, $lost_samples) {
        foreach my $mergedSortedIds (keys %{$hash}) {
            my $project_code = "";
            my $project_donor_id = "";
            foreach my $id (split /,/, $mergedSortedIds) {
                if (defined($analysis_id_to_donor->{$id})) {
                    $project_code = $analysis_id_to_donor->{$id}{project_code};
                    $project_donor_id = $analysis_id_to_donor->{$id}{project_donor_id};
                }
            }

            foreach my $created_timestamp (keys %{$hash->{$mergedSortedIds}}) {
                foreach my $sample_id (keys %{$hash->{$mergedSortedIds}{$created_timestamp}}) {
                    my $state = $hash->{$mergedSortedIds}{$created_timestamp}{$sample_id};
                    my $count = $count_since_last_seen->{$mergedSortedIds}{$created_timestamp}{$sample_id};
                    $count //= 0;
                    say $out "$mergedSortedIds\t$created_timestamp\t$sample_id\t$state\t$project_code\t$project_donor_id\t$count";
                }
            }
        }
    }
    close $out;
    # return the structures

    die;

    return($running_sample_ids, $failed_samples, $completed_samples);
}

sub parse_donors {
    my ($sample_info) = @_;

    my $donors = {};
    foreach my $center (keys %{$sample_info}) {
        foreach my $donor_id (keys %{$sample_info->{$center}}) {
            my $project_code = $sample_info->{$center}{$donor_id}{dcc_project_code};
            my $project_donor_id = $donor_id;
            if (defined $project_code) {
                $project_donor_id =~ /($project_code-)(\S+)/;
                $project_donor_id = $2;
            }
            else {
                $project_donor_id = 'unknown';
            }
            foreach my $specimen (keys %{$sample_info->{$center}{$donor_id}}) {
                next if ($specimen =~ /variant_workflow|dcc_project_code|submitter_donor_id/);
                foreach my $workflow_id (keys %{$sample_info->{$center}{$donor_id}{$specimen}}) {
                    foreach my $uuid (keys %{$sample_info->{$center}{$donor_id}{$specimen}{$workflow_id}}) {
                        foreach my $library (keys %{$sample_info->{$center}{$donor_id}{$specimen}{$workflow_id}{$uuid}}) {
                            foreach my $analysis_id (keys %{$sample_info->{$center}{$donor_id}{$specimen}{$workflow_id}{$uuid}{$library}{analysis_ids}}) {
                                $donors->{$analysis_id}{project_donor_id} = $project_donor_id;
                                $donors->{$analysis_id}{project_code} = $project_code;
                            }
                        }
                    }
                }
            }
        }
    }

    return $donors;
}

sub cluster_seqware_information {
    my ($class, $report_file, $clusters_json, $ignore_failed, $run_workflow_version, $failure_reports_dir) = @_;

    my %clusters;
    my %all_clusters;
    my $cluster_file_path;
    foreach my $cluster_json (@{$clusters_json}) {
        $cluster_file_path = "$Bin/../$cluster_json";
        die "file does not exist $cluster_file_path" unless (-f $cluster_file_path);
        my $cluster = decode_json( read_file($cluster_file_path));
        %all_clusters = %clusters;
        %clusters = (%all_clusters, %$cluster);
    }

    my (%cluster_information,
       %running_samples,
       %failed_samples,
       %completed_samples,
       $cluster_info,
       $samples_status_ids);
    my $cluster_num = 0;

    foreach my $cluster_name (keys %clusters) {
        my $cluster_metadata = $clusters{$cluster_name};
        $cluster_num++;
        #print "CLUSTER METADATA: $cluster_num NAME: $cluster_name\n";
        #print Dumper($cluster_metadata);

        ($cluster_info, $samples_status_ids)
            = seqware_information( $report_file,
                                   $cluster_name,
                                   $cluster_metadata,
                                   $run_workflow_version,
                                   $failure_reports_dir,
                                   $ignore_failed);

        foreach my $cluster (keys %{$cluster_info}) {
            $cluster_information{$cluster} = $cluster_info->{$cluster};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{running}}) {
            #$running_samples{$sample_id} = 1;
            $running_samples{$sample_id} = $samples_status_ids->{running}{$sample_id};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{failed}}) {
            $failed_samples{$sample_id} = $samples_status_ids->{failed}{$sample_id};
        }

        foreach my $sample_id (keys %{$samples_status_ids->{completed}}) {
            $completed_samples{$sample_id} = $samples_status_ids->{completed}{$sample_id};
        }

    }

    return (\%cluster_information, \%running_samples, \%failed_samples, \%completed_samples);
}

sub seqware_information {
    my ($report_file, $cluster_name, $cluster_metadata, $run_workflow_version, $failure_reports_dir, $ignore_failed) = @_;

    my $user = $cluster_metadata->{username};
    my $password = $cluster_metadata->{password};
    my $web = $cluster_metadata->{webservice};
    my $workflow_accession = $cluster_metadata->{workflow_accession};
    my $max_running = $cluster_metadata->{max_workflows};
    my $max_scheduled_workflows = $cluster_metadata->{max_scheduled_workflows};

    $max_running = 0 if ($max_running eq "");

    $max_scheduled_workflows = $max_running
          if ( $max_scheduled_workflows eq "" || $max_scheduled_workflows > $max_running);

    say $report_file "EXAMINING CLUSER: $cluster_name";

    my $workflow_information_xml = `wget --timeout=60 -t 2 -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession`;

    if ($workflow_information_xml eq '' ) {
       say "could not connect to cluster: $web";
       return;
    }

    my $xs = XML::Simple->new(ForceArray => 1, KeyAttr => 1);
    my $workflow_information = $xs->XMLin($workflow_information_xml);

    my $samples_status;
    if ($workflow_information->{name}) {
        my $workflow_runs_xml = `wget -O - --http-user='$user' --http-password=$password -q $web/workflows/$workflow_accession/runs`;
        my $seqware_runs_list = $xs->XMLin($workflow_runs_xml);
        my $seqware_runs = $seqware_runs_list->{list};

        construct_failure_reports($seqware_runs, $failure_reports_dir);
        #print Dumper($seqware_runs);

        $samples_status = find_available_clusters($report_file, $seqware_runs,
                   $workflow_accession, $samples_status, $run_workflow_version);
    }
    my $running = scalar(keys %{$samples_status->{running}});

    my $failed = scalar(keys %{$samples_status->{failed}});
    $running += $failed unless ($ignore_failed);

    my %cluster_info;
    if ($running < $max_running ) {
        say $report_file  "\tTHERE ARE $running RUNNING WORKFLOWS (OF WHICH $failed ARE FAILED) WHICH IS LESS THAN MAX OF $max_running, ADDING TO LIST OF AVAILABLE CLUSTERS";
        for (my $i=0; $i<$max_scheduled_workflows; $i++) {
            my %cluster_metadata = %{$cluster_metadata};
            $cluster_info{"$cluster_name-$i"} = \%cluster_metadata
                if ($run_workflow_version eq $cluster_metadata{workflow_version});
        }
    }
    else {
        say $report_file "\tCLUSTER HAS RUNNING WORKFLOWS, NOT ADDING TO AVAILABLE CLUSTERS";
    }

    return (\%cluster_info, $samples_status);
}

sub construct_failure_reports {
  my ($info, $failure_reports_dir) = @_;
  if ($failure_reports_dir ne "") {
    system("mkdir -p $failure_reports_dir");
    foreach my $entry (@{$info}) {
      my $status = $entry->{status}[0];
      if ($entry->{status}[0] eq 'failed' or $entry->{status}[0] eq 'completed') {
        my $cwd = $entry->{currentWorkingDir}[0];
        $cwd =~ /\/(oozie-[^\/]+)$/;
        my $uniq_name = $1;
        #print "CWD: $uniq_name\n";
        system("mkdir -p $failure_reports_dir/$status/$uniq_name");
        open OUT, ">$failure_reports_dir/$status/$uniq_name/summary.tsv" or die;
        foreach my $key (keys %{$entry}) {
          next if ($key eq "iniFile" or $key eq "stdErr" or $key eq "stdOut");
          print OUT "$key\t".$entry->{$key}[0]."\n";
        }
        close OUT;
        open OUT, ">$failure_reports_dir/$status/$uniq_name/stderr.txt" or die;
        print OUT $entry->{'stdErr'}[0];
        close OUT;
        open OUT, ">$failure_reports_dir/$status/$uniq_name/stdout.txt" or die;
        print OUT $entry->{'stdOut'}[0];
        close OUT;
        open OUT, ">$failure_reports_dir/$status/$uniq_name/workflow.ini" or die;
        print OUT $entry->{'iniFile'}[0];
        close OUT;
      }
    }
  }
}

sub find_available_clusters {
    my ($report_file, $seqware_runs, $workflow_accession, $samples_status) = @_;

    say $report_file "\tWORKFLOWS ON THIS CLUSTER";
    foreach my $seqware_run (@{$seqware_runs}) {
        my $run_status = $seqware_run->{status}->[0];

        say $report_file "\t\tWORKFLOW: ".$workflow_accession." STATUS: ".$run_status;

        my ($donor_id, $created_timestamp, $tumour_aliquote_ids, $sample_id, $merged_id);

        if ( ($donor_id, $created_timestamp, $tumour_aliquote_ids, $sample_id, $merged_id) = get_sample_info($report_file, $seqware_run))    {

            my $running_status = { 'pending' => 1,   'running' => 1,
                                   'scheduled' => 1, 'submitted' => 1 };
            $running_status = 'running' if ($running_status->{$run_status});
            #################$samples_status->{$run_status}{$tumour_aliquote_ids}{$created_timestamp}{$donor_id} = $run_status;
            $samples_status->{$run_status}{$merged_id}{$created_timestamp}{$sample_id} = $run_status;
        }
     }


     return $samples_status;
}

sub  get_sample_info {
    my ($report_file, $seqware_run) = @_;

    my @ini_file =  split "\n", $seqware_run->{iniFile}[0];

    my $created_timestamp = $seqware_run->{createTimestamp}[0];
    my %parameters;
    foreach my $line (@ini_file) {
         my ($parameter, $value) = split '=', $line, 2;
         $parameters{$parameter} = $value;
    }

    my $donor_id = $parameters{donor_id};
    my $tumour_aliquot_ids = $parameters{tumourAliquotIds};
    my $tumour_bams = $parameters{tumourBams};
    my $control_bam = $parameters{controlBam};
    my $sample_id =  $parameters{sample_id};
    my $input_meta_URLs = $parameters{gnos_input_metadata_urls};
    $input_meta_URLs //= '';
    my @urls = split /,/, $input_meta_URLs;
    $donor_id //= 'unknown';
    $sample_id //= 'unknown';

    say $report_file "\t\t\tDonor ID: $donor_id";
    say $report_file "\t\t\tSample ID: $sample_id";
    say $report_file "\t\t\tCreated Timestamp: $created_timestamp";
    my $sorted_urls = join(',', sort @urls);
    say $report_file "\t\t\tInput URLs: $sorted_urls";
    my $cwd = $parameters{currentWorkingDir};
    $cwd //= '';
    say $report_file "\t\t\tCwd: $cwd";
    my $swaccession  = $parameters{swAccession};
    $swaccession //= '';
    say $report_file "\t\t\tWorkflow Accession: $swaccession";
    say $report_file "\t\t\tTumour Aliquote Ids: $tumour_aliquot_ids";
    say $report_file "\t\t\tTumour Bams: $tumour_bams";
    say $report_file "\t\t\tTumour Control: $control_bam";
    # this is used to identify the variant calling run in the local cache file
    my @mergedIds;
    foreach my $tumor_id (split (/,/, $parameters{tumourAnalysisIds})) {
      foreach my $sub_tumor_id (split (/:/, $tumor_id)) {
        push @mergedIds, $sub_tumor_id;
      }
    }
    foreach my $norm_id (split (/,/, $parameters{controlAnalysisId})) {
      foreach my $sub_norm_id (split (/:/, $norm_id)) {
        push @mergedIds, $sub_norm_id;
      }
    }
    my @sortedMergedIds = sort @mergedIds;
    say $report_file "\t\t\tMerged Sorted IDs: ".join(",", @sortedMergedIds);

    return ($donor_id, $created_timestamp, $tumour_aliquot_ids, $sample_id, join(",", @sortedMergedIds));
}

1;
