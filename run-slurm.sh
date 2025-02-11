#!/bin/bash

# salloc --nodes=64 --job-name=koyongse --exclusive --partition dev
# JOBNAME=test ./run-slurm.sh run.sh

TIMESTAMP=$(date +%s)
JOBNAME=${JOBNAME:-${TIMESTAMP}}
JOBID=$(squeue --noheader --name koyongse --user $USER --format=%A)
DNAME="/fsx/koyongse/slurm-logs/slurm-${JOBID}.out/${JOBNAME}"
rm -rf ${DNAME}
mkdir -p ${DNAME}
date
echo $DNAME
export TEST_ARTIFACTS_PATH=${DNAME}
export NODE_N=8
squeue -j ${JOBID}

srun --nodes=${NODE_N} --jobid=${JOBID} --kill-on-bad-exit=1 --output=${DNAME}/slurm-%j-%n.log "$@"
