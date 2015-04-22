#!/usr/bin/env perl

use strict;
use warnings;

use feature 'say';
use Data::Dumper;
use autodie qw(:all);
use IPC::System::Simple;
use Getopt::Euclid;
use JSON;

#Example command perl bin/create_cluster_json.pl --inventory-file=../monitoring-bag/inventory_updated --workflow-name=SangerPancancerCgpCnIndelSnvStr > cluster.json


open my $fh, '<', $ARGV{'--inventory-file'};
while (not <$fh> =~ /^\[master\]$/) {}

my (%nodes, $target_name, %parameters);
while (<$fh>) {
    next if ($_ =~ /^#/);
    my @line = split ' ';
    $target_name = shift @line;
    %parameters = map {split /=/} @line;
    my ($workflow_version, $workflow_accession) = get_latest_workflow_version(\%parameters, $ARGV{'--workflow-name'}, $ARGV{'--specific-workflow-version'});
    next unless($workflow_version or $workflow_accession);
    $nodes{$target_name} = {
               "workflow_accession"      => $workflow_accession,
               "workflow_name"           => $ARGV{'--workflow-name'},
               "username"                => 'admin@admin.com',
               "password"                => 'admin',
               "workflow_version"        => $workflow_version,
               "webservice"              => "http://$parameters{ansible_ssh_host}:8080/SeqWareWebService",
               "host"                    => 'master',
               "max_workflows"           => 1,
               "max_scheduled_workflows" => 1 };
}

my $json = JSON->new->allow_nonref;
my $cluster_json = $json->pretty->encode(\%nodes);

print $cluster_json;

sub get_latest_workflow_version {
    my ($parameters, $workflow_name, $specific_workflow_version) = @_;

    my $std_out = `ssh -o StrictHostKeyChecking=no -o LogLevel=quiet -i $parameters{ansible_ssh_private_key_file} $parameters{ansible_ssh_user}\@$parameters{ansible_ssh_host} "sudo -u seqware -i seqware workflow list"`;

    my ($workflow_accession, $workflow_version);
    my $found_workflow = 0; 
    my $latest_workflow = 0;
    my @lines = split /\n/, $std_out;
    foreach my $line (@lines) {
        if ($found_workflow and $line =~ /^Version\s+\|\s(.*?)\s+/) {
            $found_workflow = 0;
            if (defined($specific_workflow_version)) {
                if ($specific_workflow_version eq $1) {
                    $workflow_version = $1;
                    $latest_workflow = 1;
                }
            }
            elsif (!$workflow_version or $workflow_version lt $1) {
                $workflow_version = $1;    
                $latest_workflow = 1;
            } 
            $found_workflow = 0;
        } 
        elsif ($latest_workflow and $line =~ /^SeqWare Accession\s+\|\s(.*?)\s+/) {
            $workflow_accession = $1;
            $latest_workflow = 0;
        }           
        elsif ($line =~ /^Name\s+\|\s$workflow_name/) {
            $found_workflow = 1;
        }
    }
  
   return ($workflow_version, $workflow_accession);
}
