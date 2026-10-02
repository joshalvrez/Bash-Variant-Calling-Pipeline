#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# submit.sh — two sbatch calls and one dependency.
#
#   bash submit.sh          all eight samples, then the cohort job
#   bash submit.sh 1-2      only tasks 1-2, to check it works
#-----------------------------------------------------------------------------
set -euo pipefail

# This runs on the login node as a normal script, so finding its own folder
# from BASH_SOURCE is fine here (it is the JOB scripts that cannot).
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$HERE"                     # so SLURM_SUBMIT_DIR is slurm/ for both jobs
source conf/slurm.env

RANGE=${1:-}

# Slurm does not create the --output folder, and a job that cannot open its
# log fails with nowhere to say why.
mkdir -p logs

ARRAY_ARGS=()
[[ -z "$RANGE" ]] || ARRAY_ARGS=(--array="$RANGE")

# --parsable makes sbatch print only the job id
ARRAY_ID=$(sbatch --parsable -p "$PARTITION" -A "$ACCOUNT" "${ARRAY_ARGS[@]}" 01_persample.sbatch)
echo "array   ${ARRAY_ID}"

# afterok, not afterany: the cohort job starts only if EVERY task succeeded.
# With afterany a failed sample would still let the cohort stages run on the
# rest. --kill-on-invalid-dep=yes cancels the cohort job when that can no longer
# happen, instead of leaving it PENDING forever on a cluster that does not
# cancel it by default.
COHORT_ID=$(sbatch --parsable -p "$PARTITION" -A "$ACCOUNT" \
                   --dependency=afterok:${ARRAY_ID} --kill-on-invalid-dep=yes \
                   02_cohort.sbatch)
echo "cohort  ${COHORT_ID}   (waits for ${ARRAY_ID})"
echo
echo "watch:   squeue -u \$USER"
echo "measure: seff ${ARRAY_ID}_1 ; seff ${COHORT_ID}"
echo "         sacct -j ${ARRAY_ID},${COHORT_ID} --format=JobID,State,ExitCode,Elapsed,MaxRSS,AllocCPUS"
