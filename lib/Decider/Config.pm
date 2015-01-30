package Decider::Config;

use common::sense;

use autodie qw(:all);

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Config::Simple;

use Data::Dumper;

### merges command line flags with configurations in the decider config file
sub get {
    my %ARGV = %{$_[1]};

    my $cfg = new Config::Simple();

    $cfg->read("$Bin/../$ARGV{'--decider-config'}");
    
    my %decider_config = $cfg->vars();

    # Making sure cluster file exists
    ## Also allows you to have a ';' seperated list of configuration files
    ### might need to be changed to ',' seperated because I beleive this is 
    ### config simples automatic array separator.
    my @general_seqware_clusters = split ';', $decider_config{'scheduling.seqware-clusters'};
    $ARGV{'--seqware-clusters'} //= \@general_seqware_clusters;

    foreach my $config_file (@{$ARGV{'--seqware-clusters'}}) {
        die "file does not exist: $config_file" unless (-f $config_file);
    }
    
    # Required
    my %string_flags_to_ini_keys = (
           '--seqware-setttings'     => 'general.seqware-settings',
           '--report'                => 'general.report',
           '--working-dir'           => 'general.working-dir',
           '--bwa-workflow-version'  => 'general.bwa-workflow-version',  
           '--lwp-download-timeout'  => 'general.lwp-download-timeout',
           '--local-status-cache'    => 'general.local-status-cache',
           '--failure-reports-dir'   => 'general.failure-reports-dir',
           '--workflow-name'         => 'workflow.workflow-name',
           '--workflow-version'      => 'workflow.workflow-version',
           '--tabix-url'             => 'workflow.tabix-url',
           '--gnos-download-url'     => 'workflow.gnos-download-url',
           '--gnos-upload-url'       => 'workflow.gnos-upload-url',
           '--gtdownload-pem-file'   => 'workflow.gtdownload-pem-file',
           '--gtupload-pem-file'     => 'workflow.gtupload-pem-file',
           '--cores-addressable'     => 'workflow.cores-addressable',
           '--mem-host-mb-abailable' => 'workflow.mem-host-mb-available'
    );

    my $ini_key;
    foreach my $flag (keys %string_flags_to_ini_keys) {

        $ini_key = $string_flags_to_ini_keys{$flag};
        $ARGV{$flag} //= $decider_config{$ini_key};

        die "Need to either specify flag: $flag or spefiy ini key: $ini_key"
                                                               unless $ARGV{$flag};

    }

    # Optional

    my %boolean_flags_to_ini_keys = (
            '--use-cached-analysis'        => 'general.use-cached-analysis',
            '--use-cached-xml'             => 'general.use-cached-xml',
            '--schedule-ignore-failed'     => 'scheduling.ignore-failed',
            '--schedule-force-run'         => 'scheduling.force-run',
            '--skip-scheduling'            => 'scheduling.skip-scheduling',
            '--workflow-upload-results'    => 'workflow.upload-results',
            '--workflow-skip-gtdownload'   => 'workflow-skip-gtdownload',
            '--workflow-skip-gtupload'     => 'workflow-skipt-gtupload'
    );
    
    my $ini_key;
    foreach my $flag (keys %boolean_flags_to_ini_keys) {
        $ini_key = $boolean_flags_to_ini_keys{$flag};
        $ARGV{$flag} //= ($decider_config{$ini_key} eq 'true')? 1: 0;
    }

    my %optional_flags_to_ini_keys = (
           '--schedule-whitelist-sample' => 'scheduling.whitelist-sample',
           '--schedule-blacklist-sample' => 'scheduling.blacklist-sample',
           '--schedule-whitelist-donor'  => 'scheduling.whitelist-donor',
           '--schedule-blacklist-donor'  => 'scheduling.blacklist-donor',
           '--workflow-output-dir'       => 'workflow.output-dir',
           '--workflow-output-prefix'    => 'workflow.output-prefix',
           '--workflow-input-prefix'     => 'workflow.input-prefix',
           '--cores-addressable'         => 'workflow.cores-addressable'
    );

    my $ini_key;
    foreach my $flag (keys %optional_flags_to_ini_keys) {
        $ini_key = $optional_flags_to_ini_keys{$flag};
        $ARGV{$flag} //= $decider_config{$ini_key};
    }

    return \%ARGV;
}

1;
