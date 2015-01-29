#!/usr/bin/env perl

use strict;
use warnings;

use feature 'say';

use autodie qw(:all);
use IPC::System::Simple;

use Getopt::Euclid;

use Capture::Tiny ':all';

#Example Command
## perl bin/update-whitelist.pl --pawgc-repo-dir /home/ubuntu/architecture2/ --whitelist-target-path=/home/ubuntu/architecture2/workflow-decider/whitelist/ebi-whitelist.txt --cloud-env=ebi --gnos-repo=ebi --blacklist-target-path=/home/ubuntu/architecture2/workflow-decider/blacklist/blacklist.txt

my $repo_dir  = $ARGV{'--pawgc-repo-dir'};
my $whitelist_target_path = $ARGV{'--whitelist-target-path'};
my $blacklist_target_path = $ARGV{'--blacklist-target-path'};
my $cloud_env = $ARGV{'--cloud-env'};
my $gnos_repo = $ARGV{'--gnos-repo'};
my $workflow = 'sanger_workflow';

say "\nCHECK: Does $repo_dir exists";
if (-d $repo_dir) {
    say "CONCLUSION: $repo_dir exists";
}
else {
    die "CONCLUSION: $repo_dir does not exist";
}

$repo_dir = $1 if($repo_dir=~/(.*)\/$/); # remove trailing slash if exists
my $repo_path = "$repo_dir/pcawg-operations";

say "\nCHECK: Does $repo_path exist";
if (-d $repo_path) {
    say "CONCLUSION: $repo_path exists";
}
else {
    say "CONCLUSION: $repo_path does not exist... cloning repo";
    `cd $repo_dir; git clone https://github.com/ICGC-TCGA-PanCancer/pcawg-operations.git;`
}

say 'Fetching tags from GitHub';
`cd $repo_path; git fetch --tags`;

say 'Finding latest tag';
my $stdout;
my ($latest_tag, $stderr) = capture {
   system("cd $repo_path; git describe --tags `git rev-list --tags --max-count=1`")
};
chomp $latest_tag;

say "Latest tag is $latest_tag";

say 'Checking out latest tag';

`cd $repo_path; git checkout $latest_tag`;


##Create whitelist file
my $whitelist_env_path = "$repo_path/variant_calling/$workflow/whitelists/$cloud_env";

unless (-d $whitelist_env_path) {
    die "Expecting $whitelist_env_path but it does not exist";
}
# get list of files in direcotory that do not start with '.'
opendir(my $dh, $whitelist_env_path);
my @file_list = grep { !/^\./ && -f "$whitelist_env_path/$_" } readdir($dh); 
closedir $dh;

my %files_to_consider;
say "Checking for latest file for $cloud_env from GNOS repo $gnos_repo";
foreach my $file_name (@file_list) {
    my @file_name_parts = split /\./, $file_name;

    next if (scalar @file_name_parts != 4);
    my ($file_cloud_env, $file_date, $file_descriptor, $file_extension) = @file_name_parts;
    next if $file_extension ne 'txt';
    next if $file_cloud_env ne $cloud_env;
    next unless $file_descriptor =~ /from_$gnos_repo$/;

    $files_to_consider{$file_date} = $file_name; 
}

if (!keys %files_to_consider) {
    die "Could not find files matching $cloud_env and GNOS repo $gnos_repo";
}

my $first_date = (sort keys %files_to_consider)[0];
my $lastest_date = (sort keys %files_to_consider)[-1]

say "Latest file is: $latest_file";

#Creating latest whiteliste file
my $whitelist_file_path = "$whitelist_env_path/whitelist-$first_date-to-$last_date.txt";

if (-e $whitelist_file_path) {
   say "Whitelist already exists ($whitelist_file_path): not creating";
}
else {
    open my $out_fh, '>', $whitelist_file_path;
    foreach my $date (sort keys %files_to_consider) {
        open my $in_fh, '<', $files_to_consider{$date};
        while (<$in_fh> {
             say $out_fh $_;
        }
        close $in_fh;
    }
}

say "Creating whitelist symlink:\n\tFrom $whitelist_file_path to $whitelist_target_path";

`ln -sf $whitelist_file_path $whitelist_target_path`;


##Creating blacklist file
my $blacklist_file_path = "$repo_path/variant_calling/$workflow/blacklists/_all_sites/_all_sites.latest_blacklist.txt";

unless (-f $blacklist_file_path) {
   die "can not find directory $blacklist_file_path";
}

say "Creating blacklist symlink:\n\tFrom $blacklist_file_path to $blacklist_file_path ";

`ln -sf $blacklist_file_path $blacklist_target_path`;


say "Complete!!";
