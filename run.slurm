#!/bin/bash

#SBATCH --output=/fsx/koyongse/slurm-logs/slurm-%j.log
#SBATCH --job-name=koyongse
#SBATCH --exclusive
#SBATCH --nodes=64
#SBATCH --partition dev

DNAME="/fsx/koyongse/slurm-logs/slurm-${SLURM_JOB_ID}.out"
mkdir -p ${DNAME}
date
echo $DNAME
squeue -j ${SLURM_JOB_ID}

#srun  --kill-on-bad-exit=1 --output=${DNAME}/slurm-%j-%n.log run-profile.sh "$@"
#srun  --kill-on-bad-exit=1 --output=${DNAME}/slurm-%j-%n.log run-multistream-cc.sh "$@"
srun  --kill-on-bad-exit=1 --output=${DNAME}/slurm-%j-%n.log "$@"
