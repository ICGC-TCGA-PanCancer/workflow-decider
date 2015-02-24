package SeqWare::Schedule::Sanger;
# subclass schedule for Sanger-specific variant calling workflow

use common::sense;
use Data::Dumper;
use parent 'SeqWare::Schedule';
use SeqWare::Schedule::Ini;
use FindBin qw($Bin);
use warnings;
use strict;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub factory {
    my $self = shift;
    $self->{ini_factory} ||= SeqWare::Schedule::Ini->new;
    return $self->{ini_factory};
}

sub create_workflow_settings {
    my $self = shift;
    my (
        $donor,
        $seqware_settings_file,
        $url,
        $username,
        $password,
        $output_dir,
        $center_name) = @_;

    my $factory = $self->factory;

    # may be some workflow-specific manipulations here at some point
    my $donor_id = $donor->{donor_id};
    $output_dir = "$Bin/../$output_dir/ini/$donor_id";
    $seqware_settings_file = "$Bin/../conf/seqware.setting";

    $factory->create_settings_file($donor,
        $seqware_settings_file,
        $url,
        $username,
        $password,
        $output_dir,
        $center_name);
}

sub create_workflow_ini {
    my $self = shift;
    my (
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
        $vmInstanceType,
        $vmInstanceCores,
        $vmInstanceMemGb,
        $vmLocationCode,
        $cleanupBams,
        $localFileMode,
        $localXMLMetadataPath,
        $skipValidate,
        $localBamFilePathPrefix,
        $workflow_version
        ) = @_;

    # Read in the default data
    my @normal_alignments = keys %{$donor->{normal}};
    my @tumor_alignments  = keys %{$donor->{tumor}};

    my (@normal_bam,@normal_analysis,@normal_aliquot);
    for my $aln_id (@normal_alignments) {
	push @normal_bam, $donor->{bam_ids}->{$aln_id};
	push @normal_analysis, $donor->{analysis_ids}->{$aln_id};
	push @normal_aliquot, $donor->{aliquot_ids}->{$aln_id};
    }
    my (@tumor_bam,@tumor_analysis,@tumor_aliquot);
    for my $aln_id (@tumor_alignments) {
	push @tumor_bam, $donor->{bam_ids}->{$aln_id};
	push @tumor_analysis, $donor->{analysis_ids}->{$aln_id};
	push @tumor_aliquot, $donor->{aliquot_ids}->{$aln_id};
    }

    my $data = {};
    $data->{'coresAddressable'}            = $threads;
    $data->{'tabixSrvUri'}                 = $tabix_url;
    $data->{'tumourAnalysisIds'}           = join(':',@tumor_analysis);
    $data->{'tumourAliquotIds'}            = join(':',@tumor_aliquot);
    $data->{'tumourBams'}                  = join(':',@tumor_bam);
    $data->{'controlAnalysisId'}           = join(':',@normal_analysis);
    $data->{'controlAliquotId'}            = join(':',@normal_aliquot);
    $data->{'controlBam'}                  = join(':',@normal_bam);
    $data->{'pemFile'}                     = $download_pem_file;
    $data->{'uploadPemFile'}               = $upload_pem_file;
    $data->{'gnosServer'}                  = $gnos_download_url;
    $data->{'uploadServer'}                = $gnos_upload_url;
    $data->{'donorId'}                     = $donor->{donor_id};
    $data->{'memHostMbAvailable'}          = $mem_host_mb_available;
    $data->{'cleanup'}                     = ($cleanup)? 'true':'false';
    $data->{'studyRefnameOverride'}        = $study_refname_override;
    $data->{'analysisCenterOverride'}      = $analysis_center_override;
    $data->{'seqwareOutputLinesNumber'}    = $seqware_output_lines_number;
    $data->{'testMode'}                    = ($test_mode)? 'true':'false';
    $data->{'dccPojectCode'}               = $dcc_project_code;
    # new
    $data->{'uploadTest'}                  = $uploadTest;
    $data->{'uploadSkip'}                  = $uploadSkip;
    $data->{'vmInstanceType'}              = $vmInstanceType;
    $data->{'vmInstanceCores'}             = $vmInstanceCores;
    $data->{'vmInstanceMemGb'}             = $vmInstanceMemGb;
    $data->{'vmLocationCode'}              = $vmLocationCode;
    $data->{'cleanupBams'}                 = $cleanupBams;
    $data->{'localFileMode'}               = $localFileMode;
    $data->{'localXMLMetadataPath'}        = $localXMLMetadataPath;
    $data->{'skipValidate'}                = $skipValidate;
    $data->{'localBamFilePathPrefix'}      = $localBamFilePathPrefix;
    $data->{'workflowVersion'}             = $workflow_version;

    my $template = "$Bin/../$workflow_template";

    my $ini_factory = $self->factory;
    $working_dir = "$Bin/../$working_dir/ini";
    $ini_factory->create_ini_file($working_dir,$template,$data,$donor->{donor_id});
}

1;
