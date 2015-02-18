#!/usr/bin/env perl

use strict;
use warnings;

use feature 'say';

use Data::Dumper;

use autodie qw(:all);
use IPC::System::Simple;

use Config::Simple;

use Getopt::Euclid;

use JSON;

#Example command perl bin/create_cluster_json.pl --inventory-file=../monitoring-bag/inventory_updated --workflow-name=SangerPancancerCgpCnIndelSnvStr > cluster.json

my $cfg = new Config::Simple($ARGV{'--inventory-file'});
my $worker_nodes = $cfg->param(-block=>'master');

my %nodes;
foreach my $node_key (keys %{$worker_nodes}) {
    my @node_key_parts = split ' ', $node_key;
    my $node_name = $node_key_parts[0];

    my @node_value_parts = split ' ', $worker_nodes->{$node_key};
    my $node_ip = $node_value_parts[0];
    my ($ansible_ssh_user_string, $machine_user) = split '=', $node_value_parts[1];
    my ($ssh_private_key_string, $ssh_private_key) = split '=', $node_value_parts[2];

    my ($workflow_version, $workflow_accession) = get_latest_workflow_version(
                 $node_ip, $ssh_private_key, $machine_user, $ARGV{'--workflow_name'});
    next unless($workflow_version or $workflow_accession);
    $nodes{$node_name} = {
               "workflow_accession"      => $workflow_accession,
               "workflow_name"           => $ARGV{'--workflow-name'},
               "username"                => 'admin@admin.com',
               "password"                => 'admin',
               "workflow_version"        => $workflow_version,
               "webservice"              => "http://$node_ip:8080/SeqWareWebService",
               "host"                    => 'master',
               "max_workflows"           => 1,
               "max_scheduled_workflows" => 1 };
}

my $json = JSON->new->allow_nonref;
my $cluster_json = $json->pretty->encode(\%nodes);

print $cluster_json;

sub get_latest_workflow_version {
    my ($node_ip, $ssh_private_key, $machine_user, $workflow_name) = @_;

    my $std_out = `ssh -o StrictHostKeyChecking=no -o LogLevel=quiet -i $ssh_private_key $machine_user\@$node_ip "sudo -u seqware -i seqware workflow list"`;

    my ($workflow_accession, $workflow_version);
    my $found_workflow = 0; 
    my $latest_workflow = 0;
    my @lines = split /\n/, $std_out;
    foreach my $line (@lines) {
        if ($found_workflow and $line =~ /^Version\s+\|\s(.*?)\s+/) {
            $found_workflow = 0;
            if (!$workflow_version or $workflow_version lt $1) {
                $workflow_version = $1;    
                $latest_workflow = 1;
            } 
            $found_workflow = 0;
        } 
        elsif ($latest_workflow and $line =~ /^SeqWare Accession\s+\|\s(.*?)\s+/) {
            $workflow_accession = $1;
            $latest_workflow = 0;
        }           
        elsif ($line =~ /^Name\s+\|\sSangerPancancerCgpCnIndelSnvStr/) {
            $found_workflow = 1;
        }
    }
  
   return ($workflow_version, $workflow_accession);
}
