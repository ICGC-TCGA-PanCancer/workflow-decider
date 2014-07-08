package SeqWare::Schedule;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use Term::ProgressBar;
use Config::Simple;
use Capture::Tiny ':all';
use Cwd;

use Data::Dumper;

sub schedule_samples {
    my ($class, $report_file,
                $sample_information, 
                $cluster_information, 
                $running_samples, 
                $test,
                $specific_sample,
                $ignore_lane_count,
                $seqware_settings_file,
                $output_dir,
                $output_prefix,
                $force_run,
                $threads,
                $skip_gtdownload,
                $skip_gtupload,
                $upload_results,
                $input_prefix, 
                $gnos_url,
                $ignore_failed, 
                $working_dir) = @_;
  
    say $report_file "SAMPLE SCHEDULING INFORMATION\n";

    my $progress_bar = Term::ProgressBar->new(scalar keys %{$sample_information});

    my $i = 0;
    foreach my $center_name (keys %{$sample_information}) {
        foreach my $participant_id (keys %{$sample_information->{$center_name}}) {
            my $participant_information = $sample_information->{$center_name}{$participant_id};
            schedule_participant($report_file,
                             $participant_id, 
                             $participant_information,
                             $cluster_information, 
                             $running_samples, 
                             $test,
                             $specific_sample,
                             $ignore_lane_count,
                             $seqware_settings_file,
                             $output_dir,
                             $output_prefix,
                             $force_run,
                             $threads,
                             $skip_gtdownload,
                             $skip_gtupload,
                             $upload_results,
                             $input_prefix, 
                             $gnos_url,
                             $ignore_failed, 
                             $working_dir, 
                             $center_name);
            $progress_bar->update($i++);
        }
    }
}

sub schedule_workflow {
    my ( $sample, 
         $seqware_settings_file, 
         $report_file,
         $cluster_information,
         $working_dir,
         $threads,
         $gnos_url,
         $skip_gtdownload,
         $skip_gtupload,
         $test,
         $upload_results,
         $output_prefix,
         $output_dir,
         $force_run,
         $running_samples,
         $sample_id,
         $center_name ) = @_;


    system("mkdir -p $working_dir/samples/$center_name/$sample_id");

    my $cluster = (keys %{$cluster_information})[0];
    my $cluster_found = (defined $cluster)? 1: 0;

    my $url = $cluster_information->{$cluster}{webservice};
    my $username = $cluster_information->{$cluster}{username};
    my $password = $cluster_information->{$cluster}{password};
    my $workflow_accession = $cluster_information->{$cluster}{workflow_accession};
    $workflow_accession //= 0;
    my $workflow_version = $cluster_information->{$cluster}{workflow_version};
    $workflow_version //= '2.5.0';
    my $host = $cluster_information->{$cluster}{host};
    $host //= 'unknown';

    delete $cluster_information->{$cluster};

    create_settings_file($seqware_settings_file, $url, $username, $password, $working_dir, $center_name, $sample_id);

    create_workflow_ini($workflow_version, $sample, $gnos_url, $threads, $skip_gtdownload, $skip_gtupload, $upload_results, $output_prefix, $output_dir, $working_dir, $center_name, $sample_id);

    submit_workflow($working_dir, $workflow_accession, $host, $test, $cluster_found, $report_file, $url, $center_name, $sample_id);
}

sub create_settings_file {
    my ($seqware_settings_file, $url, $username, $password, $working_dir, $center_name, $sample_id) = @_;

    my $settings = new Config::Simple("template/ini/$seqware_settings_file");

    $settings->param('SW_REST_URL', $url);
    $settings->param('SW_REST_USER', $username);
    $settings->param('SW_REST_PASS',$password);

    $settings->write("$working_dir/samples/$center_name/$sample_id/settings");
}

sub create_workflow_ini {
    my ($workflow_version, $sample, $gnos_url, $threads, $skip_gtdownload, $skip_gtupload, $upload_results, $output_prefix, $output_dir, $working_dir, $center_name, $sample_id) = @_;

    my $workflow_ini = new Config::Simple("template/ini/workflow-$workflow_version.ini" );

    $workflow_ini->param('input_bam_paths', $sample->{local_bams_string});
    $workflow_ini->param('gnos_input_file_urls', $sample->{gnos_input_file_urls});
    $workflow_ini->param('gnos_input_metadata_urls', $sample->{analysis_url});
    $workflow_ini->param('gnos_output_file_url', $gnos_url);
    $workflow_ini->param('numOfThreads', $threads);
    $workflow_ini->param('use_gtdownload', ($skip_gtdownload)? 'false': 'true');
    $workflow_ini->param('use_gtupload',  ($skip_gtupload)? 'false': 'true');
    $workflow_ini->param('skip_upload', ($upload_results)? 'false': 'true');
    $workflow_ini->param('output_prefix', $output_prefix);
    $workflow_ini->param('output_dir', $output_dir);
  
    $workflow_ini->write("$working_dir/samples/$center_name/$sample_id/workflow.ini");
}


sub submit_workflow {
    my ($working_dir, $workflow_accession, $host, $test, $cluster_found, $report_file, $url, $center_name, $sample_id) = @_;

    my $dir = getcwd();

    my $launch_command = "SEQWARE_SETTINGS=$working_dir/$center_name/$sample_id/settings /usr/local/bin/seqware workflow schedule --accession $workflow_accession --host $host --ini $working_dir/$center_name/$sample_id/workflow.ini";

    if ($test) {
        say $report_file "\tNOT LAUNCHING WORKFLOW BECAUSE --test SPECIFIED: $working_dir/$center_name/$sample_id/workflow.ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command\n";
        return;
    }
 
 
    if ($cluster_found) {
       
        say $report_file "\tLAUNCHING WORKFLOW: $working_dir/$center_name/$sample_id/workflow.ini";
        say $report_file "\t\tCLUSTER HOST: $host ACCESSION: $workflow_accession URL: $url";
        say $report_file "\t\tLAUNCH CMD: $launch_command";

        my $out_fh = IO::File->new("log/submission/$sample_id.o", "w+");
        my $err_fh = IO::File->new("log/submission/$sample_id.e", "w+");
 
        my ($std_out, $std_err) = capture {
             no autodie qw(system);
             system( "source ~/.bashrc;
                      cd $dir;
                      export SEQWARE_SETTINGS=$working_dir/$center_name/$sample_id/settings;
                      export PATH=\$PATH:/usr/local/bin;
                      env;
                     # seqware workflow schedule --accession $workflow_accession --host $host --ini $working_dir/$center_name/$sample_id/workflow.ini") } stdout => $out_fh, sterr => $err_fh;


        say $report_file "\t\tSOMETHING WENT WRONG WITH SCHEDULING THE WORKFLOW"
                                                                       if( $std_err);
    }
    else {
        say $report_file "\tNOT LAUNCHING WORKFLOW, NO CLUSTER AVAILABLE: $working_dir/$center_name/$sample_id/workflow.ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command";
    } 
    say $report_file '';
}

sub schedule_participant {
    my ( $report_file,
         $participant_id,
         $participant_information,
         $cluster_information, 
         $running_samples, 
         $test,
         $specific_sample,
         $ignore_lane_count,
         $seqware_settings_file,
         $output_dir,
         $output_prefix,
         $force_run,
         $threads,
         $skip_gtdownload,
         $skip_gtupload,
         $upload_results,
         $input_prefix, 
         $gnos_url,
         $ignore_failed,
         $working_dir,
         $center_name ) = @_;

    say $report_file "DONOR/PARTICIPANT: $participant_id\n";

    foreach my $sample_id (keys %{$participant_information}) {        
        next if (defined $specific_sample && $specific_sample eq $sample_id);

        schedule_sample( $sample_id,
                         $participant_information,
                         $report_file,
                         $gnos_url,
                         $input_prefix,
                         $force_run,
                         $running_samples,
                         $ignore_failed,
                         $ignore_lane_count,
                         $seqware_settings_file,
                         $cluster_information,
                         $working_dir,
                         $threads,
                         $skip_gtdownload,
                         $skip_gtupload,
                         $test,
                         $upload_results,
                         $output_prefix,
                         $output_dir,
                         $center_name);
    }
}

sub schedule_sample {
    my ( $sample_id,
         $participant_information, 
         $report_file,
         $gnos_url,
         $input_prefix,
         $force_run,
         $running_samples, 
         $ignore_failed,
         $ignore_lane_count, 
         $seqware_settings_file,
         $cluster_information,
         $working_dir,
         $threads,
         $skip_gtdownload,
         $skip_gtupload,
         $test,
         $upload_results,
         $output_prefix,
         $output_dir,
         $center_name) = @_;

    say $report_file "\tSAMPLE OVERVIEW\n\tSPECIMEN/SAMPLE: $sample_id";

    my $alignments = $participant_information->{$sample_id};
    my $sample = { gnos_url => $gnos_url};
    my $aligns = {};
    foreach my $alignment_id (keys %{$alignments}) {
        say $report_file "\t\tALIGNMENT: $alignment_id";

        $aligns->{$alignment_id} = 1;
        my $aliquotes = $alignments->{$alignment_id};
        foreach my $aliquot_id (keys %{$aliquotes}) {
            say $report_file "\t\t\tANALYZED SAMPLE/ALIQUOT: $aliquot_id";
            my $libraries = $aliquotes->{$aliquot_id};
            foreach my $library_id (keys %{$libraries}) {
                say $report_file "\t\t\t\tLIBRARY: $library_id";
                my $library = $libraries->{$library_id};
                my $total_lanes = $library->{total_lanes};
                foreach my $lane (keys %{$total_lanes}) {
                    $total_lanes = $lane if ($lane > $total_lanes);
                }
                $sample->{total_lanes_hash}{$total_lanes} = 1;
                $sample->{total_lanes} = $total_lanes;

                my $files = $library->{files};
                foreach my $file (keys %{$files}) {
                    my $local_path = $file->{localpath};
                    $sample->{files}{$file} = $local_path;
                    my $local_file_path = $input_prefix.$local_path;
                    $sample->{local_bams}{$local_file_path} = 1;
                    $sample->{bam_count} ++ if ($alignment_id eq "unaligned");
                }
 
                $sample->{local_bams_string} = join ',', sort keys %{$sample->{local_bams}};
                my $analysis_ids = $library->{analysis_id};

                foreach my $analysis_id (sort keys %{$analysis_ids}) {
                     $sample->{analysis_url}{"$gnos_url/cghub/metadata/analysisFull/$analysis_id"} = 1;
                     $sample->{download_url}{"$gnos_url/cghub/data/analysis/download/$analysis_id"} = 1;
                 }

                 $sample->{gnos_input_file_urls} = join ',', sort keys $sample->{download_url};
                 say $report_file "\t\t\t\t\tBAMS: ".join ',', keys %{$files};
                 my @analysis_ids =;
                 say $report_file "\t\t\t\t\tANALYSIS_IDS: ". join ',', @{ keys $analysis_ids}. "\n";
            }
        }
    }

    say $report_file "\tSAMPLE WORKLFOW ACTION OVERVIEW";
    say $report_file "\t\tLANES SPECIFIED FOR SAMPLE: $sample->{total_lanes}";
    say $report_file "\t\tBAMS FOUND: $sample->{bams_count}";
   

    schedule_workflow( $sample, 
                       $seqware_settings_file, 
                       $report_file,
                       $cluster_information,
                       $working_dir,
                       $threads,
                       $gnos_url,
                       $skip_gtdownload,
                       $skip_gtupload,
                       $test,
                       $upload_results,
                       $output_prefix,
                       $output_dir,
                       $force_run,
                       $running_samples,
                       $sample_id,
                       $center_name )
       if should_be_scheduled( $aligns, 
                               $force_run, 
                               $report_file, 
                               $sample, 
                               $running_samples, 
                               $ignore_failed, 
                               $ignore_lane_count);
}

sub should_be_scheduled {
    my ($aligns, $force_run, $report_file, $sample, $running_samples, $ignore_failed, $ignore_lane_count) = @_;

    if ((unaligned($aligns, $report_file) or scheduled($report_file, $sample, $running_samples, $sample, $force_run, $ignore_failed, $ignore_lane_count))
                                                         and $force_run) { 
        say $report_file "\t\tCONCLUSION: WILL NOT SCHEDULE THIS SAMPLE FOR ALIGNMENT!"; 
        return 0;
    }

    say $report_file "\t\tCONCLUSION: SCHEDULING WORKFLOW FOR THIS SAMPLE!\n";

    return 1;
}

sub unaligned {
    my ($aligns, $report_file) = @_;

    my $unaligned = $aligns->{unaligned};
    if  (not scalar keys %{$aligns} == 1 && not defined $unaligned ) {
        say $report_file "\t\tCONTAINS ALIGNMENT"; 
        return 1; 
    }
    
    say $report_file "\t\tONLY UNALIGNED";
    return 0;
}

sub scheduled {
    my ($report_file, $sample, $running_samples, $force_run, $ignore_failed, $ignore_lane_count ) = @_; 

    my $analysis_url_str = join ',', sort keys %{$sample->{analysis_url}};
    $sample->{analysis_url} = $analysis_url_str;

    if ( not defined($running_samples->{$analysis_url_str}) || $force_run) {
        say $report_file "\t\tNOT PREVIOUSLY SCHEDULED OR RUN FORCED!";
    } 
    elsif ($running_samples->{$analysis_url_str} eq "failed" && $ignore_failed) {
        say $report_file "\t\tPREVIOUSLY FAILED BUT RUN FORCED VIA IGNORE FAILED OPTION!";
    } 
    else {
        say $report_file "\t\tIS PREVIOUSLY SCHEDULED, RUNNING, OR FAILED!";
        say $report_file "\t\t\tSTATUS: ".$running_samples->{$analysis_url_str};
        return 1;
    }

    if ($sample->{total_lanes} == $sample->{bams_count} || $ignore_lane_count || $force_run) {
        say $report_file "\t\tLANE COUNT MATCHES OR IGNORED OR RUN FORCED: ignore_lane_count: $ignore_lane_count total lanes: $sample->{total_lanes} bam count: $sample->{bams_count}\n";
    } 
    else {
        say $report_file "\t\tLANE COUNT MISMATCH!";
        return 1;
    }

    return 0;
}

1;
