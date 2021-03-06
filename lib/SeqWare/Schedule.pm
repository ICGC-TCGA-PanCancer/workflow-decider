package SeqWare::Schedule;

use common::sense;

use IPC::System::Simple;
use autodie qw(:all);

use FindBin qw($Bin);

use Config::Simple;
use Capture::Tiny ':all';
use Cwd;
use Carp::Always;

use Data::Dumper;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub schedule_samples {
    my $self = shift;
    my %args = @_;

    # Still clunky but a least args won't get mixed up if they
    # are in the wrong order
    my $report_file                 = $args{'report_file'};
    my $sample_information          = $args{'sample_information'};
    my $cluster_information         = $args{'cluster_information'};
    my $running_samples             = $args{'running_sample_ids'};
    my $failed_samples              = $args{'failed_sample_ids'};
    my $completed_samples           = $args{'completed_sample_ids'};
    my $skip_scheduling             = $args{'skip-scheduling'};
    my $specific_sample             = $args{'schedule-sample'};
    my $specific_donor              = $args{'schedule-center'};
    my $specific_center             = $args{'schedule-donor'};
    my $ignore_lane_count           = $args{'schdeule-ignore-lane-count'};
    my $seqware_settings_file       = $args{'seqware-settings'};
    my $output_dir                  = $args{'workflow-output-dir'};
    my $output_prefix               = $args{'workflow-output-prefix'};
    my $force_run                   = $args{'schedule-force-run'};
    my $threads                     = $args{'cores-addressable'};
    my $mem_host_mb_available       = $args{'mem-host-mb-available'};
    my $skip_gtdownload             = $args{'workflow-skip-gtdownload'};
    my $skip_gtupload               = $args{'workflow-skip-gtdownload'};
    my $upload_results              = $args{'workflow-upload-results'};
    my $input_prefix                = $args{'workflow-input-prefix'};
    my $gnos_download_url           = $args{'gnos-download-url'};
    my $gnos_upload_url             = $args{'gnos-upload-url'};
    my $ignore_failed               = $args{'schedule-ignore-failed'};
    my $working_dir                 = $args{'working-dir'};
    my $workflow_version            = $args{'workflow-version'};
    my $workflow_name               = $args{'workflow-name'};
    my $bwa_workflow_version        = $args{'bwa-workflow-version'};
    my $tabix_url                   = $args{'tabix-url'};
    my $download_pem_file           = $args{'gtdownload-pem-file'};
    my $upload_pem_file             = $args{'gtupload-pem-file'};
    my $whitelist                   = $args{'whitelist'};
    my $blacklist                   = $args{'blacklist'};
    my $cleanup                     = $args{'workflow-cleanup'};
    my $study_refname_override      = $args{'study-refname-override'};
    my $analysis_center_override    = $args{'analysis-center-override'};
    my $seqware_output_lines_number = $args{'seqware-output-lines-number'};
    my $test_mode                   = $args{'test-mode'};
    my $workflow_template           = $args{'workflow-template'};
    my $generate_all_ini_files      = $args{'generate-all-ini-files'};
    # new
    my $uploadTest                  = $args{'upload-test'};
    my $uploadSkip                  = $args{'upload-skip'};
    my $vmInstanceType              = $args{'vm-instance-type'};
    my $vmInstanceCores             = $args{'vm-instance-cores'};
    my $vmInstanceMemGb             = $args{'vm-instance-mem-gb'};
    my $vmLocationCode              = $args{'vm-location-code'};
    my $cleanupBams                 = $args{'cleanup-bams'};
    my $localFileMode               = $args{'local-file-mode'};
    my $localXMLMetadataPath        = $args{'local-xml-metadata-path'};
    my $skipValidate                = $args{'skip-validate'};
    my $localBamFilePathPrefix      = $args{'local-bam-file-path-prefix'};

    say $report_file "SAMPLE SCHEDULING INFORMATION\n";

    my $i = 0;
    foreach my $center_name (keys %{$sample_information}) {
        next if (defined $specific_center && $specific_center ne $center_name);
        say $report_file "SCHEDULING: $center_name";

        my @blacklist = grep {s/\s+/-/} @{$blacklist->{donor}} if $blacklist and $blacklist->{donor};
        my @whitelist = grep {s/\s+/-/} @{$whitelist->{donor}} if $whitelist and $whitelist->{donor};

        DONOR: foreach my $donor_id (keys %{$sample_information->{$center_name}}) {
            # Only do specified donor if applicable
            next if defined $specific_donor and $specific_donor ne $donor_id;

            # Skip any blacklisted donors
            if (@blacklist > 0 and grep {/^$donor_id$/} @blacklist) {
              say $report_file "SKIPPING DONOR $donor_id SINCE IT IS ON THE BLACKLIST!";
              next DONOR;
            }
            if (@whitelist > 0 and !grep {/^$donor_id$/} @whitelist) {
              say $report_file "SKIPPING DONOR $donor_id SINCE IT IS NOT ON THE WHITELIST!";
              next DONOR;
            }

            # Skip any donors who already have the applicable major version of a
            # variant-calling workflow run
            my $variant_workflow = $sample_information->{$center_name}->{$donor_id}->{variant_workflow};
            delete $sample_information->{$center_name}->{$donor_id}->{variant_workflow}; # or else mess up specimen count
            if ($variant_workflow && ref $variant_workflow eq 'HASH') {
                if (my $variant_workflow_version = $variant_workflow->{$workflow_name} ) {
                    my @have_version = split '.', $variant_workflow_version;
                    my @need_version = split '.', $workflow_version;
                    # FIXME: not sure this is going to work when we have > workflow versions... seems like it will cause everything to re-run when 1.1.0 comes out! Not sure we want that...
                    my $skip_donor = $have_version[0] >= $need_version[0] && $have_version[1] >= $need_version[1];
                    if ($skip_donor && !$generate_all_ini_files) {
                        say $report_file "Skipping donor $donor_id because $workflow_name has already been run";
                        next DONOR;
                        }
                }
            }

            # put in the running+failed+completed
            my $unavail_samples = {};
            foreach my $key (keys %{$running_samples}) {
                $unavail_samples->{$key} = 1;
            }
            unless ($ignore_failed) {
                foreach my $key (keys %{$failed_samples}) {
                    $unavail_samples->{$key} = 1;
                }
            }
            foreach my $key (keys %{$completed_samples}) {
                $unavail_samples->{$key} = 1;
            }

            # Skip non-whitelisted donors if applicable
            my $on_whitelist = grep {/^$donor_id/} @whitelist;

            if (scalar(@whitelist) == 0 or $on_whitelist) {

                say $report_file "\nDONOR $donor_id is on the whitelist" if $on_whitelist and scalar(@whitelist) > 0;

                my $donor_information = $sample_information->{$center_name}{$donor_id};

                $self->schedule_donor($report_file,
                                      $donor_id,
                                      $donor_information,
                                      $cluster_information,
                                      $unavail_samples,
                                      $skip_scheduling,
                                      $specific_sample,
                                      $ignore_lane_count,
                                      $seqware_settings_file,
                                      $output_dir,
                                      $output_prefix,
                                      $force_run,
                                      $threads,
                                      $mem_host_mb_available,
                                      $skip_gtdownload,
                                      $skip_gtupload,
                                      $upload_results,
                                      $input_prefix,
                                      $gnos_download_url,
                                      $gnos_upload_url,
                                      $ignore_failed,
                                      $working_dir,
                                      $center_name,
                                      $workflow_version,
                                      $bwa_workflow_version,
                                      $whitelist,
                                      $blacklist,
                                      $tabix_url,
                                      $download_pem_file,
                                      $upload_pem_file,
                                      $cleanup,
                                      $study_refname_override,
                                      $analysis_center_override,
                                      $seqware_output_lines_number,
                                      $test_mode,
                                      $workflow_template,
                                      $generate_all_ini_files,
                                      # new
                                      $uploadSkip,
                                      $uploadTest,
                                      $vmInstanceType,
                                      $vmInstanceCores,
                                      $vmInstanceMemGb,
                                      $vmLocationCode,
                                      $cleanupBams,
                                      $localFileMode,
                                      $localXMLMetadataPath,
                                      $skipValidate,
                                      $localBamFilePathPrefix,
                                      $workflow_name
                                      );
            }
            elsif (@whitelist > 0) {
                # FIXME: can remove this since I added the check earlier in the loop
                say $report_file "Donor $donor_id is not on the whitelist";
            }
        }
    }
}

sub schedule_workflow {
    my $self = shift;

    my ( $donor,
         $seqware_settings_file,
         $report_file,
         $cluster_information,
         $working_dir,
         $gnos_download_url,
         $gnos_upload_url,
         $skip_gtdownload,
         $skip_gtupload,
         $skip_scheduling,
         $upload_results,
         $output_prefix,
         $output_dir,
         $force_run,
         $threads,
         $mem_host_mb_available,
         $center_name,
         $workflow_version,
         $bwa_workflow_version,
         $tabix_url,
         $download_pem_file,
         $upload_pem_file,
         $cleanup,
         $study_refname_override,
         $analysis_center_override,
         $seqware_output_lines_number,
         $test_mode,
         $workflow_template,
         $generate_all_ini_files,
         $dcc_project_code,
         # new
         $uploadSkip,
         $uploadTest,
         $vmInstanceType,
         $vmInstanceCores,
         $vmInstanceMemGb,
         $vmLocationCode,
         $cleanupBams,
         $localFileMode,
         $localXMLMetadataPath,
         $skipValidate,
         $localBamFilePathPrefix,
         $workflow_name
        ) = @_;

    my $cluster = (keys %{$cluster_information})[0];
    my $cluster_found = (defined($cluster) and $cluster ne '' )? 1: 0;

    my $url = $cluster_information->{$cluster}{webservice};
    my $username = $cluster_information->{$cluster}{username};
    my $password = $cluster_information->{$cluster}{password};

    say "URL $url USERNAME $username PASS $password";

    my $workflow_accession = $cluster_information->{$cluster}{workflow_accession};
    $workflow_version = $cluster_information->{$cluster}{workflow_version} if $cluster_information->{$cluster}{workflow_version};
    my $host = $cluster_information->{$cluster}{host};

    my $donor_id = $donor->{donor_id};

    if ($cluster_found or $skip_scheduling or $generate_all_ini_files) {
        system("mkdir -p $Bin/../$working_dir/ini");
        $self->create_workflow_settings(
            $donor,
            $seqware_settings_file,
            $url,
            $username,
            $password,
            $working_dir,
            $center_name
            );

        $self->create_workflow_ini(
            $donor,
            $workflow_version,
            $gnos_download_url,
            $gnos_upload_url,
            $threads,
            $mem_host_mb_available,
            $skip_gtdownload,
            $skip_gtupload,
            $upload_results,
            $output_prefix,
            $output_dir,
            $working_dir,
            $center_name,
            $tabix_url,
            $download_pem_file,
            $upload_pem_file,
            $cleanup,
            $study_refname_override,
            $analysis_center_override,
            $seqware_output_lines_number,
            $test_mode,
            $workflow_template,
            $dcc_project_code,
            # new
            $uploadSkip,
            $uploadTest,
            $vmInstanceType,
            $vmInstanceCores,
            $vmInstanceMemGb,
            $vmLocationCode,
            $cleanupBams,
            $localFileMode,
            $localXMLMetadataPath,
            $skipValidate,
            $localBamFilePathPrefix,
            $workflow_name
            );
    }

    $self->submit_workflow(
       $working_dir,
       $workflow_accession,
       $host,
       $skip_scheduling,
       $cluster_found,
       $report_file,
       $url,
       $center_name,
       $donor_id
       ) unless ($generate_all_ini_files);

    delete $cluster_information->{$cluster} if ($cluster_found);
}

sub submit_workflow {
    my $self = shift;
    my ($working_dir,
        $accession,
        $host,
        $skip_scheduling,
        $cluster_found,
        $report_file,
        $url,
        $center_name,
        $donor_id) = @_;

    my $dir = getcwd();
    $working_dir =  "$Bin/../$working_dir/ini/$donor_id";
    my $ini = "$working_dir/workflow.ini";
    my $settings = "$working_dir/settings";
    my $launch_command = "SEQWARE_SETTINGS=$settings /usr/local/bin/seqware workflow schedule --accession $accession --host $host --ini $ini";

    say "LAUNCH: $launch_command";

    if ($skip_scheduling) {
        say "\tNOT LAUNCHING WORKFLOW BECAUSE --schedule-skip-workflow SPECIFIED: $ini";
        say $report_file "\tNOT LAUNCHING WORKFLOW BECAUSE --schedule-skip-workflow SPECIFIED: $ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command\n";
        return;
    }
    elsif ($cluster_found) {
        say "\tLAUNCHING WORKFLOW: $ini";
        say $report_file "\tLAUNCHING WORKFLOW: $ini";
        say $report_file "\t\tCLUSTER HOST: $host ACCESSION: $accession URL: $url";
        say $report_file "\t\tLAUNCH CMD: $launch_command";

        my $submission_path = 'log/submission';
        `mkdir -p $submission_path`;
        my $out_fh = IO::File->new("$Bin/../$submission_path/$donor_id.o", "w+");
        my $err_fh = IO::File->new("$Bin/../$submission_path/$donor_id.e", "w+");

        my ($std_out, $std_err) = capture {
             no autodie qw(system);
             system( "cd $dir;
                      export SEQWARE_SETTINGS=$settings;
                      export PATH=\$PATH:/usr/local/bin;
                      env;
                      seqware workflow schedule --accession $accession --host $host --ini $ini")
        };

        print $out_fh $std_out if($std_out);
        print $err_fh $std_err if($std_err);

        say $report_file "\t\tSOMETHING WENT WRONG WITH SCHEDULING THE WORKFLOW: Check error log =>  ",
        "$Bin/../$submission_path/$donor_id.e and output log => $Bin/../$submission_path/$donor_id.o" if $std_err;
    }
    else {
        print "\tNOT LAUNCHING WORKFLOW, NO CLUSTER AVAILABLE: $ini\n";
        say $report_file "\tNOT LAUNCHING WORKFLOW, NO CLUSTER AVAILABLE: $ini";
        say $report_file "\t\tLAUNCH CMD WOULD HAVE BEEN: $launch_command";
    }
    say $report_file '';
}

sub schedule_donor {
    my $self = shift;
    my ( $report_file,
         $donor_id,
         $donor_information,
         $cluster_information,
         $running_samples,
         $skip_scheduling,
         $specific_sample,
         $ignore_lane_count,
         $seqware_settings_file,
         $output_dir,
         $output_prefix,
         $force_run,
         $threads,
         $mem_host_mb_available,
         $skip_gtdownload,
         $skip_gtupload,
         $upload_results,
         $input_prefix,
         $gnos_download_url,
         $gnos_upload_url,
         $ignore_failed,
         $working_dir,
         $center_name,
         $workflow_version,
         $bwa_workflow_version,
         $whitelist,
         $blacklist,
         $tabix_url,
         $download_pem_file,
         $upload_pem_file,
         $cleanup,
         $study_refname_override,
         $analysis_center_override,
         $seqware_output_lines_number,
         $test_mode,
         $workflow_template,
         $generate_all_ini_files,
         # new
         $uploadSkip,
         $uploadTest,
         $vmInstanceType,
         $vmInstanceCores,
         $vmInstanceMemGb,
         $vmLocationCode,
         $cleanupBams,
         $localFileMode,
         $localXMLMetadataPath,
         $skipValidate,
         $localBamFilePathPrefix,
         $workflow_name
        ) = @_;

    say $report_file "GOING TO SCHEDULE";
    say $report_file "\nDONOR/PARTICIPANT: $donor_id\n";

    my @sample_ids = keys %{$donor_information};

    my $dcc_project_code = $donor_information->{dcc_project_code};
    my $submitted_donor_id;

    #print "DOES THIS CONTAIN VAR CALLING!?!?\n";
    #print Dumper($donor_information);

    my @samples;

    # We need to track the tissue type
    my (%tumor,%normal);
    my $aligns = {};

    my $donor = {};
    my %aliquot;

    my @blacklist = @{$blacklist->{sample}} if $blacklist and $blacklist->{sample};
    my @whitelist = @{$whitelist->{sample}} if $whitelist and $whitelist->{sample};

    my (%specimens,%aligned_specimens);

    foreach my $donor_id (@sample_ids) {

      # this is an ugly hack since I had to use this structure to pass around some extra info
      # need to skip any "donors" that are named below because they aren't really donors!
      next if ($donor_id eq "submitter_donor_id" || $donor_id eq "dcc_project_code");
        $specimens{$donor_id}++;

        next if defined $specific_sample and $specific_sample ne $donor_id;

        next if @blacklist > 0 and grep {/^$donor_id$/} @blacklist;

        if (@whitelist == 0 or grep {/^$donor_id$/} @whitelist) {

            my $alignments = $donor_information->{$donor_id};

            push @{$donor->{gnos_download_url}}, $gnos_download_url;

            my %said;

            foreach my $alignment_id (keys %{$alignments}) {

                # Skip unaligned BAMs, not relevant to VC workflows
                my $aliquots = $alignments->{$alignment_id};
                foreach my $aliquot_id (keys %{$aliquots}) {
                    $donor->{aliquot_ids}->{$alignment_id} = $aliquot_id;

                    my $libraries = $aliquots->{$aliquot_id};
                    foreach my $library_id (keys %{$libraries}) {
                        my $library = $libraries->{$library_id};


                        my $current_bwa_workflow_version = $library->{bwa_workflow_version};
                        my @current_bwa_workflow_version = keys %$current_bwa_workflow_version;
                        $current_bwa_workflow_version = $current_bwa_workflow_version[0];

                        my @current_bwa_workflow_version = split /\./, $current_bwa_workflow_version;
                        my @run_bwa_workflow_versions = split /\./, $bwa_workflow_version;


                        # Should add to list of aligns if the BWA workflow has already been run
                        # and the first two version numbers are equal to the
                        # desired BWA workflow version.
                        if (
                            defined $current_bwa_workflow_version
                            and $current_bwa_workflow_version[0] == $run_bwa_workflow_versions[0]
                            and $current_bwa_workflow_version[1] == $run_bwa_workflow_versions[1]
                            ) {
                            $aligns->{$alignment_id} = 1;
                        }
                        else {
                          print "VAR CALLING? $alignment_id\n";
                          # I think thi is where the variant calling will be
                        }

                        next unless $aligns->{$alignment_id};

                        #
                        # If we got here, we have a useable alignment
                        #
                        $aligned_specimens{$donor_id}++;

                        $aliquot{$alignment_id} = $aliquot_id;

                        my ($dcc_specimen_type) = keys %{$library->{dcc_specimen_type}};
                        # safer way to tell
                        # see https://wiki.oicr.on.ca/display/PANCANCER/PCAWG+%28a.k.a.+PCAP+or+PAWG%29+Sequence+Submission+SOP+-+v1.0
                        # the Appendix has a list of all possible terms.
                        if ($dcc_specimen_type =~ /normal/i) {
                            $normal{$alignment_id}++;
                        }
                        elsif ($dcc_specimen_type =~ /tumou?r|xenograft|cell line/i) {
                            $tumor{$alignment_id}++;
                        }
                        else {
                            say STDERR "This is an unknown sample type!";
                        }

                        # We can't use this!
                        next unless keys %tumor or keys %normal;

                        my $sample_type = $normal{$alignment_id} ? 'NORMAL' : $tumor{$alignment_id} ? 'TUMOR' : 'UNKNOWN';

                        say $report_file "\tSAMPLE OVERVIEW\n\tSPECIMEN/SAMPLE: $donor_id ($sample_type)" unless $said{$donor_id}++;

                        say $report_file "\t\tALIGNMENT: $alignment_id ";
                        say $report_file "\t\t\tANALYZED SAMPLE/ALIQUOT: $aliquot_id";
                        say $report_file "\t\t\t\tLIBRARY: $library_id";

                        my $files = $library->{files};
                        my @local_bams;
                        foreach my $file (keys %{$files}) {
                            my $local_path = $files->{$file}{local_path};
                            push @local_bams, $local_path if ($local_path =~ /bam$/);
                            $donor->{bam_ids}->{$alignment_id} = $local_path;
                        }

                        my @analysis_ids = keys %{$library->{analysis_ids}};
                        my $analysis_ids = join ',', @analysis_ids;

                        say $report_file "\t\t\t\t\tBAMS: ".join ',', @local_bams;
                        say $report_file "\t\t\t\t\tANALYSIS IDS: $analysis_ids\n";

                        $donor->{analysis_ids}->{$alignment_id} = @analysis_ids;
                        $donor->{alignment_genome} = $library->{alignment_genome};
                        $donor->{library_strategy} = $library->{library_strategy};

                        foreach my $file (keys %{$files}) {
                            my $local_path = $files->{$file}{local_path};
                            if ($local_path =~ /bam$/) {
                                $donor->{file}->{$file} = $local_path;
                                my $local_file_path = $input_prefix.$local_path;
                                $donor->{local_bams}{$local_file_path} = 1;
                                $donor->{bam_count} ++;
                            }


                            my @local_bams = keys %{$donor->{local_bams}};

                            $donor->{local_bams_string} = join ',', sort @local_bams;

                            foreach my $analysis_id (sort @analysis_ids) {
                                $donor->{analysis_url}->{"$gnos_download_url/cghub/metadata/analysisFull/$analysis_id"} = 1;
                                $donor->{download_url}->{"$gnos_download_url/cghub/data/analysis/download/$analysis_id"} = 1;
                            }

                            push @{$donor->{donor_id}},$donor_id;
                        }
                    }
                }
            }
        }
    }

    $donor->{gnos_download_url} = join(',',@{$donor->{gnos_download_url}});

    my @download_urls = sort keys %{$donor->{download_url}};
    $donor->{gnos_input_file_urls} = join(',',@download_urls);
    my @analysis_urls = sort keys %{$donor->{analysis_url}};
    $donor->{analysis_url_string} = join(',',@analysis_urls);

    say $report_file "\tDONOR WORKLFOW ACTION OVERVIEW";
    say $report_file "\t\tALIGNED BAMS FOUND: $donor->{bam_count}";

    # We want the most recent alignment for a given aliquot if there are > 1
    # First, relate time stamp to alignment IDs
    my %aln_date;
    for my $aln (keys %normal, keys %tumor) {
        my ($timestamp) = reverse split /\s+/, $aln;
        $aln_date{$aln} = $timestamp;
    }

    # Next, grab the youngest alignment for each aliquot
    my %youngest_aln_aliquot;
    for my $aln (keys %normal, keys %tumor) {
        my $aliquot   = $aliquot{$aln};
        my $timestamp = $aln_date{$aln};
        my $alignment = $youngest_aln_aliquot{$aliquot};

        if (not $alignment) {
            $youngest_aln_aliquot{$aliquot} = $aln;
        }
        else {
            my ($youngest) = reverse sort ($timestamp,$aln_date{$alignment});
            if ($timestamp eq $youngest) {
                $youngest_aln_aliquot{$aliquot} = $aln;
            }
        }
    }

    # Then relate back to the alignmend IDs in the tumor and normal hashes
    # Change keys from aliquot ID to alignment ID
    my %youngest_aln;
    for my $aliquot (keys %youngest_aln_aliquot) {
        $youngest_aln{$youngest_aln_aliquot{$aliquot}}++;
    }

    # Then remove older alignments from the tumor and normal sets
    for my $aln (keys %normal) {
        unless ($youngest_aln{$aln}) {
            delete $normal{$aln};
        }
    }
    for my $aln (keys %tumor) {
        unless ($youngest_aln{$aln}) {
            delete $tumor{$aln};
        }
    }

    # Make sure we have both tumor(s) and control
    my $unpaired_specimens = not (keys %normal and keys %tumor);

    # Make sure all samples for this donor are accounted for
    my $missing_sample = (keys %specimens) != (keys %aligned_specimens);

    #print Dumper (\%specimens);
    #print Dumper (\%aligned_specimens);
    #print Dumper $missing_sample;

    if ($unpaired_specimens) {
        say $report_file "This set is missing a tumor or control; skipping";
        return 1;
    }

    if ($missing_sample) {
        say $report_file "Not all samples have been aligned for this donor; skipping...";
        return 1;
    }

    my $kept = (keys %tumor) + (keys %normal);
    say $report_file "\t\tALIGNED BAMS RETAINED FOR VARIANT CALLING: $kept\n";

    say $report_file "Donor $donor_id ready for Variant calling";

    $donor->{donor_id} = $donor_id;
    for my $analysis (keys %{$donor->{analysis_ids}}) {
        my ($actual_id) = $analysis =~ /^\S+ - (\S+)/;
        $donor->{analysis_ids}->{$analysis} = $actual_id;
    }
    $donor->{normal} = \%normal;
    $donor->{tumor}  = \%tumor;

    say $report_file "\nABOUT TO SCHEDULE $donor_id";

    $self->schedule_workflow( $donor,
                              $seqware_settings_file,
                              $report_file,
                              $cluster_information,
                              $working_dir,
                              $gnos_download_url,
                              $gnos_upload_url,
                              $skip_gtdownload,
                              $skip_gtupload,
                              $skip_scheduling,
                              $upload_results,
                              $output_prefix,
                              $output_dir,
                              $force_run,
                              $threads,
                              $mem_host_mb_available,
                              $center_name,
                              $workflow_version,
                              $bwa_workflow_version,
                              $tabix_url,
                              $download_pem_file,
                              $upload_pem_file,
                              $cleanup,
                              $study_refname_override,
                              $analysis_center_override,
                              $seqware_output_lines_number,
                              $test_mode,
                              $workflow_template,
                              $generate_all_ini_files,
                              $dcc_project_code,
                              # new
                              $uploadSkip,
                              $uploadTest,
                              $vmInstanceType,
                              $vmInstanceCores,
                              $vmInstanceMemGb,
                              $vmLocationCode,
                              $cleanupBams,
                              $localFileMode,
                              $localXMLMetadataPath,
                              $skipValidate,
                              $localBamFilePathPrefix,
                              $workflow_name
        )
        if $self->should_be_scheduled(
            $report_file,
            $skip_scheduling,
            $running_samples,
            $donor, $center_name, $generate_all_ini_files
        );
}

sub should_be_scheduled {
    my $self = shift;
    my $report_file = shift;
    my $skip_scheduling = shift;
    my $running_samples = shift;
    my $donor = shift;
    my $center_name = shift;
    my $generate_all_ini_files = shift;

    say $report_file "GENERATE ALL INI?: $generate_all_ini_files\n";

    # just return true if we want the ini
    return(1) if ($generate_all_ini_files);

    # running_samples here actually contains running, failed, and completed
    my $prev_failed_running_complete = $self->previously_failed_running_or_completed($donor, $running_samples);

    if ($prev_failed_running_complete) {
    say $report_file "\t\tCONCLUSION: NOT SCHEDULING FOR VCF, PREVIOUSLY FAILED, RUNNING, OR COMPLETED";
      #print "\t\t\tCONCLUSION: NOT SCHEDULING FOR VCF, PREVIOUSLY FAILED, RUNNING, OR COMPLETED\n";
      return 0;
    }
    elsif ($skip_scheduling) {
      say $report_file "\t\tCONCLUSION: SKIPPING SCHEDULING SINCE SKIP-SCHEDULING SELECTED";
      #print "\t\tCONCLUSION: SKIPPING SCHEDULING SINCE SKIP-SCHEDULING SELECTED\n";
      return 0;
    }
    else {
      say $report_file "\t\tCONCLUSION: SCHEDULING FOR VCF";
      #print "\t\tCONCLUSION: SCHEDULING FOR VCF\n";
      return 1;
    }
}

sub previously_failed_running_or_completed {
    my $self = shift;
    my ($donor, $running_samples) = @_;

    my @want_to_run;

    foreach my $key (keys %{$donor->{normal}}) {
      foreach my $sub_key (split(/:/, $donor->{analysis_ids}{$key})) {
        push @want_to_run, $sub_key;
      }
    }
    foreach my $key (keys %{$donor->{tumor}}) {
      foreach my $sub_key (split (/:/, $donor->{analysis_ids}{$key})) {
        push @want_to_run, $sub_key;
      }
    }

    my $want_to_run_str = join (",", sort(@want_to_run));
    my $previously_run = 0;
    # now check
    foreach my $key (keys %{$running_samples}) {
      if ($key eq $want_to_run_str) { $previously_run = 1; }
      print "RUNNING SAMPLE: $key WANT TO RUN: $want_to_run_str PREVIOUSLY RUN BOOL: $previously_run\n";
    }
    print "PREVIOUSLY RUN: $previously_run\n";

    return($previously_run);
}

sub scheduled {
    my $self = shift;
    my ($report_file,
        $donor,
        $running_samples,
        $force_run,
        $ignore_failed,
        $ignore_lane_count ) = @_;

    my $analysis_url_str = join ',', sort keys %{$donor->{analysis_url}};
    $donor->{analysis_url} = $analysis_url_str;

    my $donor_id = $donor->{donor_id};

    if (( not exists($running_samples->{$donor_id})
        and not exists($running_samples->{$analysis_url_str})) or $force_run) {
        say $report_file "\t\tNOT PREVIOUSLY SCHEDULED OR RUN FORCED!";
    }
    elsif (( (exists($running_samples->{$donor_id}{failed})
             and (scalar keys %{$running_samples->{$donor_id}} == 1))
             or  ( exists($running_samples->{$analysis_url_str}{failed})
             and (scalar keys %{$running_samples->{$analysis_url_str}} == 1)))
             and $ignore_failed) {
        say $report_file "\t\tPREVIOUSLY FAILED BUT RUN FORCED VIA IGNORE FAILED OPTION!";
    }
    else {
        say $report_file "\t\tIS PREVIOUSLY SCHEDULED, RUNNING, OR FAILED!";
        say $report_file "\t\t\tSTATUS:".join ',',keys %{$running_samples->{donor_id}};
        return 1;
    }

    if ($donor->{total_lanes} == $donor->{bam_count} || $ignore_lane_count || $force_run) {
        say $report_file "\t\tLANE COUNT MATCHES OR IGNORED OR RUN FORCED: ignore_lane_count: ",
        "$ignore_lane_count total lanes: $donor->{total_lanes} bam count: $donor->{bams_count}\n";
    }
    else {
        say $report_file "\t\tLANE COUNT MISMATCH!";
        return 1;
    }

    return 0;
}

1;
