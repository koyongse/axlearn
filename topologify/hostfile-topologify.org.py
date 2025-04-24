#!/usr/bin/env python3
#
# Take a hostfile (like one generated from the output of
# ./list_compute_nodes in SimpleCluster or a file generated from
# `/opt/slurm/bin/scontrol show hostname $SLURM_NODELIST`, and sort it
# so that adjoining ranks are as close as possible in the network
# topology.  Default is to print to stdout, although an output file
# can be specified.

import botocore
import boto3
import argparse
import sys
import socket
import time

# It's poor form to slam a large request into the EC2 APIs, so only
# run pagination_count entries through the search loops at a time.
pagination_count = 64


def generate_topology_csv(input_file, output_file):
    ec2_client = boto3.client('ec2', None)

    done = False

    network_to_hostname = {}

    while not done:
        hostname_to_ip = {}
        ip_to_hostname = {}
        instanceid_to_hostname = {}

        # translate hostname to private ip, since PCluster uses custom
        # hostnames that the EC2 control plane doesn't see.
        for i in range(pagination_count):
            hostname = input_file.readline()
            if not hostname:
                done = True
                break
            hostname = hostname.strip()

            ip = None
            for i in range(5):
                try:
                    ip = socket.gethostbyname(socket.getfqdn(hostname))
                except:
                    time.sleep(1)
                else:
                    break
            if ip == None:
                print("Error getting ip address for %s" % (hostname))
                sys.exit(1)

            hostname_to_ip[hostname] = ip
            ip_to_hostname[ip] = hostname

        if len(ip_to_hostname.keys()) == 0:
            break

        # build instanceid -> hostname map by describing all the ips
        # and matching ip to instance id, then translating through
        # hostname_to_ip.
        #
        # The network-interface.addresses filter happens *after*
        # pagination, so we need to properly handle pagination here.
        pagination_done = False
        next_token = ""
        while not pagination_done:
            response = ec2_client.describe_instances(
                Filters=[
                    {
                        'Name': 'network-interface.addresses.private-ip-address',
                        'Values': list(ip_to_hostname.keys())
                    }
                ],
                MaxResults=pagination_count,
                NextToken=next_token)

            if 'NextToken' in response:
                next_token = response['NextToken']
            else:
                pagination_done = True

            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    instanceid = instance['InstanceId']
                    for network_interface in instance['NetworkInterfaces']:
                        private_ip = network_interface['PrivateIpAddress']
                        if private_ip in ip_to_hostname:
                            instanceid_to_hostname[instanceid] = ip_to_hostname[private_ip]

        # in what I'm sure is a bug, the default MaxResults of 20 is
        # applied even when InstanceIDs is set (MaxResults should
        # implicitly be set to the number of InstanceIds, similar to
        # all the other APIs).  Assuming the default won't change
        # scares me, so instead just tokenize.
        pagination_done = False
        next_token = ""
        while not pagination_done:
            response = ec2_client.describe_instance_topology(
                InstanceIds=list(instanceid_to_hostname.keys()),
                NextToken=next_token)

            if 'NextToken' in response:
                next_token = response['NextToken']
            else:
                pagination_done = True

            for instance in response['Instances']:
                instanceid = instance['InstanceId']

                # The public documents only say that NetworkNodes[2]
                # is more specific than NetworkNode[1] and so on.
                # Internally, we know that the lowest level is the
                # t1/brick and the next layer up is the t2/spine.
                t2_node = instance['NetworkNodes'][1]
                t1_node = instance['NetworkNodes'][2]

                if network_to_hostname.get(t2_node) == None:
                    network_to_hostname[t2_node] = {}
                if network_to_hostname[t2_node].get(t1_node) == None:
                    network_to_hostname[t2_node][t1_node] = []
                network_to_hostname[t2_node][t1_node].append(
                    instanceid_to_hostname[instanceid])

    for t2 in network_to_hostname:
        for t1 in network_to_hostname[t2]:
            for hostname in network_to_hostname[t2][t1]:
                output_file.write("%s\n" % (hostname))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate placement information in CSV formation",
    )
    parser.add_argument(
        "--output",
        help="Output file to write (default: stdout)",
        default=None
    )
    parser.add_argument(
        "--input",
        help="input hostfile",
        required=True,
        default=None
    )

    args = parser.parse_args()

    if args.output != None:
        output_file_handle = open(args.output, "w")
    else:
        output_file_handle = sys.stdout

    input_file_handle = open(args.input, "r")

    generate_topology_csv(input_file_handle, output_file_handle)

    input_file_handle.close()
    if args.output != None:
        output_file_handle.close()
