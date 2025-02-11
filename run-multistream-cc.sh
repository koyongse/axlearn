#!/usr/bin/env bash

# sbatch run.slurm run-multistream-cc.sh
# tail -f /fsx/koyongse/slurm-logs/slurm-<jobid>.out/slurm-*-0.log

# Enable dubug dump
#DEBUG_DUMP=1

# Topologify
#HOSTFILE_TOPOLOGIFIED=/fsx/koyongse/topologify/hosts.topologify

# Neuron env vars for distributed training based on SLURM
if [ -n "${HOSTFILE_TOPOLOGIFIED}" ]; then
    nodes=$(cat ${HOSTFILE_TOPOLOGIFIED})
else
    nodes=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
fi

num_nodes=${NODE_N:-$(echo "$nodes" | wc -l)}
echo "${num_nodes} nodes"
devices_per_node=64
MASTER_ADDR=$(echo "$nodes" | head -n 1)
MASTER_PORT=41000
JAX_COORDINATOR_PORT=41001

HOMEDIR="/fsx/koyongse"

export NEURON_RT_ROOT_COMM_ID="${MASTER_ADDR}:${MASTER_PORT}"
export NEURON_PJRT_PROCESSES_NUM_DEVICES=$(printf '%s,' $(seq 1 $num_nodes | xargs -I {} echo $devices_per_node) | sed 's/,$//')
if [ -n "${HOSTFILE_TOPOLOGIFIED}" ]; then
    export NEURON_PJRT_PROCESS_INDEX=$(($(grep -n "\<$(hostname)\>" ${HOSTFILE_TOPOLOGIFIED} | cut -d: -f1) - 1))
else
    export NEURON_PJRT_PROCESS_INDEX=$SLURM_NODEID
fi
echo "NEURON_PJRT_PROCESS_INDEX=${NEURON_PJRT_PROCESS_INDEX}"

# Needed for TC_MALLOC fix
sudo apt-get -f install -y
sudo apt-get install -y google-perftools

sudo dpkg -r aws-neuronx-tools aws-neuronx-devtools
sudo dpkg -i ${HOMEDIR}/debs/tools/aws-neuronx-tools-*.deb ${HOMEDIR}/debs/tools/aws-neuronx-devtools-*.deb

#sudo dpkg -i ${HOMEDIR}/neuron/aws-neuronx-dkms_2.x_amd64.deb
#[[ $? != 0 ]] && exit 1

sudo dpkg -r aws-neuronx-collectives aws-neuronx-runtime-lib
#sudo dpkg -i ${HOMEDIR}/debs/rtnccl/aws-neuronx-collectives*.deb ${HOMEDIR}/debs/rtnccl/aws-neuronx-runtime-lib*.deb

# Print nodenames for debug
echo $(hostname) : $(cat /sys/devices/virtual/dmi/id/board_asset_tag)

JOB_ID=${SLURM_JOB_ID}
ARTIFACTS_PATH="${HOMEDIR}/slurm-logs"
TEST_ARTIFACTS_PATH=${TEST_ARTIFACTS_PATH:-"${ARTIFACTS_PATH}/slurm-${JOB_ID}.out"}
mkdir -p "$TEST_ARTIFACTS_PATH"
NEURON_DUMP_PATH=${TEST_ARTIFACTS_PATH}/neuron_dump
HLO_DUMP_PATH=${TEST_ARTIFACTS_PATH}/hlo_dump

export XLA_FLAGS="--xla_disable_hlo_passes=aws_neuron_flip_all_gather_dot,neuron-hierarchical-collectives"
if [ -n "$DEBUG_DUMP" ]; then
    export XLA_FLAGS="${XLA_FLAGS} --xla_dump_hlo_as_text --xla_dump_to=${HLO_DUMP_PATH} --xla_dump_hlo_pass_re='.*'"
fi

# PJRT Flags 
export NEURON_FSDP_NUM_LAYER_EARLY_AG_SHIFT=1
export NEURON_FSDP_NUM_LAYER_LATE_RS_SHIFT=2
export NEURON_ENABLE_INT_MATMUL_DOWNCAST=1
export NEURON_FSDP=1
export NEURON_FSDP_NUM_LAYER_COALESCE=-1
export NEURON_FSDP_CC_MULTISTREAM=1
export NEURON_RUN_TRIVIAL_COMPUTATION_ON_CPU=1

if [ -n "$DEBUG_DUMP" ]; then
    export TF_CPP_MIN_LOG_LEVEL=0
    export TF_CPP_MAX_VLOG_LEVEL=0
    export TF_CPP_VMODULE="neuron_token_threading=10,neuron_fsdp_all_gather_split=10,neuron_hierarchical_collectives=10,neuron_all_gather_combiner=10,neuron_reduce_scatter_combiner=10"
fi
#export TF_DUMP_GRAPH_PREFIX=${HLO_DUMP_PATH}

# Neuron runtime flags
if [ ${NEURON_FSDP_CC_MULTISTREAM} -eq 1 ]; then
    export NEURON_RT_DBG_CC_DMA_PACKET_SIZE=65536,4096
else
    export NEURON_RT_DBG_CC_DMA_PACKET_SIZE=4096
fi
export NEURON_RT_DBG_DMA_PACKETIZATION_SIZE=104857
export NEURON_RT_ASYNC_EXEC_MAX_INFLIGHT_REQUESTS=1
export NEURON_RT_IO_RING_CACHE_SIZE=0
export NEURON_RT_VIRTUAL_CORE_SIZE=2
export NEURON_RT_RESET_CORES=1
export NEURON_RT_LOG_LEVEL="WARNING"
export NEURON_RT_ENABLE_INTERNODE_EXECUTION_BARRIER=1
export NEURON_RT_CC_ALG_TYPES=^INTER_RDH_ALG

#export NEURON_RT_INSPECT_ENABLE=1
#export NEURON_RT_INSPECT_OUTPUT_DIR="${TEST_ARTIFACTS_PATH}/profile"
#neuron-profile view -d ./output --output-format perfetto

# Neuron collectives flag
export FI_LOG_LEVEL="warn"
export OFI_NCCL_PROTOCOL=RDMA
export LD_LIBRARY_PATH="${HOMEDIR}/neuron/lib:/opt/amazon/efa/lib/"
export FI_EFA_USE_DEVICE_RDMA="1"
export FI_PROVIDER="efa"
export FI_EFA_FORK_SAFE=1
export OFI_NCCL_MR_CACHE_DISABLE=1

# Neuron compiler flags
export NEURON_CC_FLAGS="--framework=XLA"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-max-instruction-limit=20000000"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --target=trn2"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-num-neuroncores-per-sengine=2"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --model-type transformer"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --no-internal-hlo-remat"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --enable-mixed-precision-accumulation"
#export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-enable-dge-levels spill_reload"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-disable-dge-levels spill_reload"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --auto-cast=none"
export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} -O1"
#export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-backend-options=' --spill-reload-dmas-use-swdge '"

if [ ${NEURON_FSDP_CC_MULTISTREAM} -eq 1 ]; then
    export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-hlo2tensorizer-options='--remat-rope --disable-early-opt-barrier-removal' --ccop-pipeline-buffer-size=2000"
    if [ -n "$DEBUG_DUMP" ]; then
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --dump=${NEURON_DUMP_PATH}"
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --tensorizer-options='--enable-hoist-fsdp-collectives --dump-after=All'"
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-backend-options='--run-shared-allocation-before-post-sched=true --enable-perf-sim'"
    else
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --tensorizer-options='--enable-hoist-fsdp-collectives'"
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-backend-options='--run-shared-allocation-before-post-sched=true'"
    fi
else
    export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-hlo2tensorizer-options='--remat-rope'"
    if [ -n "$DEBUG_DUMP" ]; then
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --dump=${NEURON_DUMP_PATH}"
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --tensorizer-options='--enable-hoist-fsdp-collectives --dump-after=All'"
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --internal-backend-options='--enable-perf-sim'"
    else
        export NEURON_CC_FLAGS="${NEURON_CC_FLAGS} --tensorizer-options='--enable-hoist-fsdp-collectives'"
    fi
fi

# JAX Cache
export JAX_COMPILATION_CACHE_DIR="${TEST_ARTIFACTS_PATH}/jax_cache"
mkdir -p ${JAX_COMPILATION_CACHE_DIR}

deactivate
# conda
# eval "$(/fsx/apoorvgu/conda/bin/conda shell.bash hook)"
# conda activate py310

source ${HOMEDIR}/venvs/jax/bin/activate

echo "Listing apt dependencies"
apt list --installed | grep neuron
echo "Listing pip dependencies"
pip list | grep neuron
echo "Done listing dependencies"
printenv | grep NEURON
printenv | grep XLA
which python
cat /opt/amazon/efa_installed_packages

# TC MALLOC HACK
LIBTCMALLOC=$(find /usr/lib/x86_64-linux-gnu -name "libtcmalloc.so.*" | sort -V | tail -n 1)
 
if [ -n "$LIBTCMALLOC" ]; then
    # Create a symbolic link to the found libtcmalloc version
    sudo ln -sf "$LIBTCMALLOC" /usr/lib/libtcmalloc.so
    echo "Symbolic link created: /usr/lib/libtcmalloc.so -> $LIBTCMALLOC"
 
    # Export LD_PRELOAD
    export LD_PRELOAD=/usr/lib/libtcmalloc.so
    echo "LD_PRELOAD set to: $LD_PRELOAD"
else
    echo "Error: libtcmalloc.so not found"
    exit 1
fi

OUTPUT_DIR="${TEST_ARTIFACTS_PATH}/axlearn_out"
mkdir -p ${OUTPUT_DIR}
DATA_DIR="gs://axlearn-public/tensorflow_datasets"

python -m axlearn.common.launch_trainer_main \
    --module=text.gpt.c4_trainer --config=fuji-70B-v2-flash \
    --trainer_dir=$OUTPUT_DIR --data_dir=$DATA_DIR \
    --jax_backend=neuron --mesh_selector=neuron-trn2.48xlarge-64 \
    --distributed_coordinator=$MASTER_ADDR:$JAX_COORDINATOR_PORT --num_processes=$num_nodes \
    --process_id=$NEURON_PJRT_PROCESS_INDEX
