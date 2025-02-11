#!/usr/bin/env bash

# sbatch --nodes=1 --job-name koyongse --partition=dev --exclusive --output=/fsx/koyongse/tmp/artifacts/slurm-%j.log run-multistream-cc.sh
# tail -f $(ls -t /fsx/koyongse/tmp/artifacts/slurm-*.log | head -1)

# Neuron env vars for distributed training based on SLURM
set -x
nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
num_nodes=$(echo "$nodes" | wc -l)
echo "${num_nodes} nodes"

devices_per_node=64
MASTER_ADDR=$(echo "$nodes" | head -n 1)
MASTER_PORT=41000
JAX_COORDINATOR_PORT=41001

HOMEDIR="/fsx/koyongse"

export NEURON_RT_ROOT_COMM_ID="${MASTER_ADDR}:${MASTER_PORT}"
export NEURON_PJRT_PROCESSES_NUM_DEVICES=$(printf '%s,' $(seq 1 $num_nodes | xargs -I {} echo $devices_per_node) | sed 's/,$//')
export NEURON_PJRT_PROCESS_INDEX=$SLURM_NODEID

hostname
set +x
exit 0
