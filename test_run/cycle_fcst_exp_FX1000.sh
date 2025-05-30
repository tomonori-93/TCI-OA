#!/bin/bash
# これは cycle_FX1000.sh で実行した同化結果を初期値に予報を行うための
# 環境設定を行うスクリプト.
# 予報実行までは行わない.
#===============================================================================
#
#  Wrap cycle.sh in an FX1000 job script and run it.
#
#-------------------------------------------------------------------------------
#
#  Usage:
#    cycle_FX1000.sh [..]
#  Author: Satoki Tsujino (Modified from cycle_ofp.sh)
#
#===============================================================================

cd "$(dirname "$0")"
myname="$(basename "$0")"
job='cycle'

#===============================================================================
# Configuration

. ./config.main || exit $?
. ./config.${job} || exit $?

. src/func_distribute.sh || exit $?
. src/func_datetime.sh || exit $?
. src/func_util.sh || exit $?
. src/func_${job}.sh || exit $?

#-------------------------------------------------------------------------------

echo "[$(datetime_now)] Start $myname $@"

setting "$@" || exit $?

if [ "$CONF_MODE" = 'static' ]; then
  . src/func_common_static.sh || exit $?
  . src/func_${job}_static.sh || exit $?
fi

echo
print_setting || exit $?
echo

#===============================================================================
# Create and clean the temporary directory

echo "[$(datetime_now)] Create and clean the temporary directory"

#if [ -e "${TMP}" ]; then
#  echo "[Error] $0: \$TMP will be completely removed." >&2
#  echo "        \$TMP = '$TMP'" >&2
#  exit 1
#fi
safe_init_tmpdir $TMP || exit $?

#===============================================================================
# Determine the distibution schemes

echo "[$(datetime_now)] Determine the distibution schemes"

declare -a node_m
declare -a name_m
declare -a mem2node
declare -a mem2proc
declare -a proc2node
declare -a proc2group
declare -a proc2grpproc

safe_init_tmpdir $NODEFILE_DIR || exit $?
if ((IO_ARB == 1)); then                              ##
  distribute_da_cycle_set - $NODEFILE_DIR || exit $?  ##
else                                                  ##
  distribute_da_cycle - $NODEFILE_DIR || exit $?
fi                                                    ##

#===============================================================================
# Determine the staging list

echo "[$(datetime_now)] Determine the staging list"

cat $SCRP_DIR/config.main | \
    sed -e "/\(^DIR=\| DIR=\)/c DIR=\"$DIR\"" \
    > $TMP/config.main

echo "SCRP_DIR=\"\$TMPROOT\"" >> $TMP/config.main
echo "RUN_LEVEL=4" >> $TMP/config.main

echo "PARENT_REF_TIME=$PARENT_REF_TIME" >> $TMP/config.main

safe_init_tmpdir $STAGING_DIR || exit $?
if [ "$CONF_MODE" = 'static' ]; then
  staging_list_static || exit $?
  config_file_list $TMPS/config || exit $?
else
  staging_list || exit $?
fi

#-------------------------------------------------------------------------------
# Add shell scripts and node distribution files into the staging list

cat >> ${STAGING_DIR}/${STGINLIST} << EOF
${SCRP_DIR}/config.rc|config.rc
${SCRP_DIR}/config.${job}|config.${job}
${SCRP_DIR}/${job}.sh|${job}.sh
${SCRP_DIR}/src/|src/
EOF

if [ "$CONF_MODE" != 'static' ]; then
  echo "${SCRP_DIR}/${job}_step.sh|${job}_step.sh" >> ${STAGING_DIR}/${STGINLIST}
fi

#===============================================================================

if ((IO_ARB == 1)); then                                              ##
  echo "${SCRP_DIR}/sleep.sh|sleep.sh" >> ${STAGING_DIR}/${STGINLIST} ##
  NNODES=$((NNODES*2))                                                ##
  NNODES_APPAR=$((NNODES_APPAR*2))                                    ##
fi                                                                    ##

#===============================================================================
# Stage in

echo "[$(datetime_now)] Initialization (stage in)"

stage_in server || exit $?

#===============================================================================
# Creat a job script

jobscrp="$TMP/${job}_job.sh"

echo "[$(datetime_now)] Create a job script '$jobscrp'"

if ((NNODES > 768)); then
  rscgrp="fx-special"
elif ((NNODES > 192)); then
  rscgrp="fx-xlarge"
elif ((NNODES > 96)); then
  rscgrp="fx-large"
elif ((NNODES > 24)); then
  rscgrp="fx-middle"
else
  rscgrp="fx-small"
fi

cat > $jobscrp << EOF
#!/bin/sh
# Satoki Tsujino
#PJM --rsc-list "rscunit=fx"
#PJM --rsc-list "rscgrp=${rscgrp}"
#PJM --rsc-list "node=${NNODES}:noncont"
#PJM --rsc-list "elapse=${TIME_LIMIT}"
#PJM --mpi "rank-map-bychip"
#PJM --mpi "proc=$((NNODES*PPN))"

cd \${PJM_O_WORKDIR}
echo "cd \${PJM_O_WORKDIR}"

export OMP_NUM_THREADS=${THREADS}
export PARALLEL=${THREADS}
export MPI_NUM_PROCS=$totalnp
export OMP_STACKSIZE=5120000
module unload netcdf-c netcdf-fortran phdf5 hdf5
module load netcdf-c/4.7.3 netcdf-fortran/4.5.2 phdf5/1.10.6 hdf5/1.10.6
module list

sh ./${job}.sh "$STIME" "$ETIME" "$ISTEP" "$FSTEP" "$CONF_MODE" || exit \$?
#sh -x ./${job}.sh "$STIME" "$ETIME" "$ISTEP" "$FSTEP" "$CONF_MODE" || exit \$?
EOF

#===============================================================================
# Run the job

echo "[$(datetime_now)] Finish configuration for fcst_exp..."
echo

exit

job_submit_PJM $jobscrp
echo

job_end_check_PJM $jobid
res=$?

#===============================================================================
# Stage out

#satoki echo "[$(datetime_now)] Finalization (stage out)"

#satoki stage_out server || exit $?

#===============================================================================
# Finalization

echo "[$(datetime_now)] Finalization"
echo

backup_exp_setting $job $TMP $jobid ${job}_job.sh 'o e'

if [ "$CONF_MODE" = 'static' ]; then
  config_file_save $TMPS/config || exit $?
fi

archive_log

#if ((CLEAR_TMP == 1)); then
#  safe_rm_tmpdir $TMP
#fi

#===============================================================================

echo "[$(datetime_now)] Finish $myname $@"

exit $res
echo "Pass check satoki"; exit
