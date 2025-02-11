#!/usr/bin/env bash

# NEFF_DIR=$(ls -td /fsx/koyongse/tmp/artifacts/slurm-*.out | head -1)/neuron_dump/pid*-program0 sbatch --nodes=1 --job-name koyongse --partition=dev --exclusive --chdir ${NEFF_DIR} --output=profile.log /fsx/koyongse/axlearn/run-profile.sh file.neff

# salloc -N 1 -J koyongse -p dev --exclusive  
# /fsx/koyongse/axlearn/run-profile.sh file.neff |& tee profile.log

NEFF_FILE=$1
NEFF_FNAME=$(basename -- "${NEFF_FILE}")
NEFF_DNAME=$(dirname -- "${NEFF_FILE}")
NEFF_NAME="${NEFF_FNAME%.*}"
pwd
date

HOMEDIR="/fsx/koyongse"
sudo dpkg -r aws-neuronx-tools aws-neuronx-devtools
sudo dpkg -i ${HOMEDIR}/debs/tools/aws-neuronx-tools-*.deb ${HOMEDIR}/debs/tools/aws-neuronx-devtools-*.deb

#sudo dpkg -i ${HOMEDIR}/neuron/aws-neuronx-dkms_2.x_amd64.deb
#[[ $? != 0 ]] && exit 1

sudo dpkg -r aws-neuronx-collectives aws-neuronx-runtime-lib
#sudo dpkg -i ${HOMEDIR}/debs/rtnccl/aws-neuronx-collectives*.deb ${HOMEDIR}/debs/rtnccl/aws-neuronx-runtime-lib*.deb

#echo "Listing apt dependencies"
#apt list --installed | grep neuron
#printenv | grep NEURON
#printenv | grep XLA

# Print nodenames for debug
echo $(hostname) : $(cat /sys/devices/virtual/dmi/id/board_asset_tag)

cat /opt/amazon/efa_installed_packages

set -x
NODE_ID=$SLURM_NODEID
NODE_N=$SLURM_NNODES
INTRA_RANK_N=64

NODE_LIST=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
ROOT_HOSTNAME=$(echo "${NODE_LIST}" | head -n 1)

LD_LIBRARY_PATH=/fsx/koyongse/neuron/lib:/opt/amazon/efa/lib/ \
NEURON_RT_LOG_LEVEL=ERROR \
NEURON_RT_IO_RING_CACHE_SIZE=0 \
NEURON_RT_VIRTUAL_CORE_SIZE=2 \
NEURON_RT_RESET_CORES=1 \
NEURON_RT_ENABLE_INTERNODE_EXECUTION_BARRIER=1 \
NEURON_RT_DBG_CC_DMA_PACKET_SIZE=65536,4096 \
NEURON_RT_DBG_DMA_PACKETIZATION_SIZE=104857 \
NEURON_RT_VIRTUAL_CORE_SIZE=2 \
NEURON_RT_ROOT_COMM_ID=${ROOT_HOSTNAME}:62181 \
OFI_NCCL_PROTOCOL=RDMA \
OFI_NCCL_MR_CACHE_DISABLE=1 \
/opt/aws/neuron/bin/neuron-profile capture \
    --neff ${NEFF_FILE} --session-file ${NEFF_DNAME}/${NEFF_NAME}.ntff \
    --collectives-profile-id=0 --collectives-worker-start-id=$((INTRA_RANK_N*NODE_ID)) \
    --collectives-workers-per-node=${INTRA_RANK_N} \
    --collectives-worker-count=$((INTRA_RANK_N*NODE_N)) \
    --num-exec=2 --profile-nth-exec=2

ls -al ${NEFF_DNAME}/*.ntff
set +x
