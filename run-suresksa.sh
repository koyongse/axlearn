#!/usr/bin/env bash

export TEST_ARTIFACTS_PATH=/home/ubuntu/koyongse/logs/${TESTNAME}
export NODE_N=1
export SLURM_NODEID=0
./run-multistream-cc.sh |& tee ${TEST_ARTIFACTS_PATH}/log.out
