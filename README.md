# BWA Decider

## About

This is the decider for the PanCancer Variant Calling workfow.


## Installing dependencies

A shell script named 'install' will install all of the dependencies.

           sudo bash install

## Configuration

./conf/decider.ini Is an example decider config file that provides the decider with all the parameters that it needs. 
./conf/ini contains seqware ini templates fore submitting workflows to SeqWare. This template file is set in thee decider ini with the parameterfile is pointed to in the decider.ini file (section: workflow parameter: workflow-template). If need be this is where you will adjust the memory settings for the workflow. 

## White/Black lists
Place donor and sample-level white or black lists in the appropriate directory.
For example a white list of donor IDs is placed in the whitelist directory, then
specified as follows:

           whitelist-donor=donors_I_want.txt
           
           Other options:
           blacklist-donor=
           whitelist-sample=
           blacklist-sample=

Each list is a text file with one donor or sample ID/line

An script has been created for creating these files from a github repo (https://github.com/ICGC-TCGA-PanCancer/pcawg-operations):

           perl bin/update-whitelist.pl --pawgc-repo-dir /home/ubuntu/architecture2/ --whitelist-target-path=/home/ubuntu/architecture2/workflow-decider/whitelist/ebi-whitelist.txt --cloud-env=ebi --gnos-repo=ebi --blacklist-target-path=/home/ubuntu/architecture2/workflow-decider/blacklist/blacklist.txt

The cloud environment is the same name as the folder in the repo that you are getting your whitelist from and the gnos-repo is exactly the sample as the name at the end of the file in the repo (eg. from_ebi.txt). 

Place the names of the two files into your decider.ini.

           whitelist-donor=etri-whitelist-bsc.txt
           blacklist-donor=blacklist.txt

## Running the decider

           perl bin/sanger_workflow_decider.pl --decider-config=conf/<decider-file>

Before you run the decider make sure to update the whitelist files from the repository.           

## Testing

For testing purposes you can set the following flag to true: skip-scheduling=true

Look at the logs to determine if the decider is doing things as you would expect.

#Flags

All settings can be maind in the devider.ini file. Several of the parameters that are in the ini files can be overwritten with command line flags. The following descibes these flags:

<pre>
VERSION
     This document refers to sanger_workflow_decider.pl version 1.1.0

AUTHOR(S)
    Brian O'Connor, Adam Wright, Sheldon McKay

    --usage
    --help
    --man
        Print the usual program information

DESCRIPTION
    A tool for identifying samples ready for alignment, scheduling on
    clusters, and monitoring for completion.

NAME
     sanger_workflow_decider.pl - SeqWare


REQUIRED
    --decider-config[=][ ]<decider_path>
        The path to the file containing the default settings for the decider.
        If another option is chosen via command line option the command line
        setting will take precedence.

OPTIONS
    --seqware-clusters[=][ ]<file>
        JSON file that describes the clusters available to schedule workflows
        to. As a reference there is a cluster.json file in the conf folder.

    --local-status-cache[=][ ]<file>
        Tab-seperated file describing the previous aliquot-ids that were
        scheduled, completed, failed, or running. This is not particularly
        workflow-agnostic but it's used when working with Youxia since VMs can
        be retired at any time. By having the decider cache these knowledge
        about what has been run previously and failed is retained.

    --failure-reports-dir[=][ ]<failure-report-dir>
        This is the directory to which failures reports will be logged. This
        is extremely useful if the hosts workflow are running on are ephemeral
        and disappear often.

    --workflow-name[=][ ]<workflow_name>
        Specify the variant caller workflow name to be run (eq
        SangerPancancerCgpCnIndelSnvStr)

    --workflow-version[=][ ]<workflow_version>
        Specify the variant caller workflow version you would like to run (eg.
        1.0.1)

    --bwa-workflow-version[=][ ]<workflow_version>
        Specify the bwa workflow required to proceed to variant calling (eg
        2.6.0)

    --gnos-download-url[=][ ]<gnos_url>
        URL for a GNOS server, e.g. https://gtrepo-ebi.annailabs.com

    --gnos-upload-url[=][ ]<gnos_upload_url>
        URL for a GNOS server to upload (if different from --gnos-url)

    --working-dir[=][ ]<working_directory>
        A place for temporary ini and settings files

    --use-cached-analysis
        A flag indicating that previously download analysis xml files for each
        analysis event should not be downloaded again

    --seqware-settings[=][ ]<seqware_settings>
        The template seqware settings file

    --report[=][ ]<report_file>
        The report file name that the results will be placed in by the decider

    --use-cached-xml
        Use the previously downloaded list of files from GNOS that are marked
        in the live state (only useful for testing).

    --tabix-url[=][ ]<tabix_url>
        The URL of the tabix server

    --gtdownload-pem-file[=][ ]<path_to_download_pem_file>
        Path to pem file on worker node that is used for dowloading from GNOS

    --gtupload-pem-file[=][ ]<path_to_upload_pem_file>
        Path to pem file on worker node that is used for uploading to GNOS

    --lwp-download-timeout[=][ ]<wait_time>
        This flag is used to specify the amount of time lwp download should
        wait for an xml file. If zero is specified it will skip lwp download
        and attempt other methods.

    --schedule-ignore-failed
        A flag indicating that previously failed runs for this specimen should
        be ignored and the specimen scheduled again

    --schedule-whitelist-sample[=][ ]<filename>
        This flag indicates the file that contains a list of sample ids to be
        analyzed. This file should be placed in the whitelist folder and
        should have one sample id per line.

    --schedule-whitelist-donor[=][ ]<filename>
        This flag indicates a file that contains a list of donor ids to be
        analyzed. This file should be placed in the whitelist folder and
        should have one "project_code\tdonor_id" per line.

    --schedule-blacklist-sample[=][ ]<filename>
        This flag indicates samples that should not be run. The file should be
        placed in the blacklist folder and should have one sample id per line.

    --schedule-blacklist-donor[=][ ]<filename>
        This flag indicates donors that should not be run. The file should be
        placed in the blacklist folder and should have one
        "project_code\tdonor_id" per line.

    --schedule-sample[=][ ]<aliquot_id>
        For only running one particular sample based on its uuid

    --schedule-donor[=][ ]<aliquot_id>
        For running one particular donor based on its uuid

    --schedule-ignore-lane-count
        Skip the check that the GNOS XML contains a count of lanes for this
        sample and the bams count matches

    --schedule-force-run
        Schedule workflows even if they were previously completed

    --cores-addressable[=][ ]<number of cores>
        The number of cores that can be used for the analysis

    --skip-scheduling
        Indicates workflows should not be scheduled, just summary of what
        would have been run.

    --workflow-upload-results
        A flag indicating the resulting VCF files and metadata should be
        uploaded to GNOS, default is to not upload!!!

    --workflow-skip-gtdownload
        A flag indicating that input files should be just the bam input paths
        and not from GNOS

    --workflow-skip-gtupload
        A flag indicating that upload should not take place but output files
        should be placed in output_prefix/output_dir

    --workflow-output-prefix[=][ ]<output_prefix>
        If --skip-gtupload is set, use this to specify the prefix of where
        output files are written

    --workflow-output-dir[=][ ]<output_directory>
        if --skip-gtupload is set, use this to specify the dir of where output
        files are written

    --workflow-input-prefix[=][ ]<prefix>
        if --skip-gtdownload is set, this is the input bam file prefix

</pre>

