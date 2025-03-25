#!/bin/sh
# Satoki Tsujino
#PJM --rsc-list "rscunit=fx"
#PJM --rsc-list "rscgrp=fx-small"
#PJM --rsc-list "node=8:noncont"
#PJM --rsc-list "elapse=24:00:00"
#PJM --mpi "rank-map-bychip"
#PJM --mpi "proc=64"

cd ${PJM_O_WORKDIR}
echo "cd ${PJM_O_WORKDIR}"

export OMP_NUM_THREADS=6
export PARALLEL=6
export MPI_NUM_PROCS=64
export OMP_STACKSIZE=5120000
module unload netcdf-c netcdf-fortran phdf5 hdf5
module load netcdf-c/4.7.3 netcdf-fortran/4.5.2 phdf5/1.10.6 hdf5/1.10.6
module list

sh ./cycle.sh "20180923000000" "20180923000000" "1" "5" "static" || exit $?
#sh -x ./cycle.sh "20180923000000" "20180923000000" "1" "5" "static" || exit $?
