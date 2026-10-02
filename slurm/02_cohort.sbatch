#!/bin/bash
#SBATCH --job-name=w2-cohort
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --output=logs/cohort_%j.out
#SBATCH --export=NONE
#-----------------------------------------------------------------------------
# Stages 6-9, once, after every array task has succeeded.
#
# No analysis happens in this file. It runs the WHOLE pipeline on the FULL
# samplesheet from stage 0: stages 0-5 find each sample's output already on disk
# and skip, so there is no "start at stage 6" argument to get wrong.
#
# submit.sh submits this with --dependency=afterok on the array, so it only
# starts if all eight tasks exited 0.
#
# The three resource lines above were measured, not guessed (RESOURCES.md):
#   --cpus-per-task=2  1.04 cores busy; the cohort stages are single-threaded
#   --mem=4G           peak was 1.19 GiB; the first request was 8G
#   --time=00:30:00    the job took 8:57; the first request was 01:00:00
#-----------------------------------------------------------------------------
set -euo pipefail

# $SLURM_SUBMIT_DIR, not $(dirname "$0"): Slurm runs a COPY of this script from
# its own spool folder, so $0 does not point into slurm/.
if [[ ! -s "${SLURM_SUBMIT_DIR}/conf/slurm.env" ]]; then
    echo "no conf/slurm.env in ${SLURM_SUBMIT_DIR}; submit from slurm/ or use: bash submit.sh" >&2
    exit 78
fi
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

if [[ ! -s "${PIPELINE_DIR}/run_pipeline.sh" ]]; then
    echo "no run_pipeline.sh in ${PIPELINE_DIR}; set PIPELINE_DIR in conf/slurm.env" >&2
    exit 78
fi

# The tools come from my image. Nothing is loaded or activated here: the last
# line of this script runs the pipeline inside the .sif.
if [[ ! -s "${SIF}" ]]; then
    echo "no image at ${SIF}; fetch it first: sbatch pull.sbatch" >&2
    exit 78
fi

export THREADS="${SLURM_CPUS_PER_TASK}"      # set from Slurm, not typed as a number

# Node-local temporary space; stage 6's intermediate goes here. Removed by the
# trap however the job ends.
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "cohort on $(hostname), ${SLURM_CPUS_PER_TASK} cores, run root ${RUN_ROOT}"
# Run the pipeline inside the image.
#   --cleanenv  nothing from this job's environment crosses into the container
#   --env       ...except the variables named here, which the pipeline reads
#   --bind      the container sees home, /tmp and the submit directory by
#               itself; the course data and my run directory have to be added
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}"

CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak (bytes): $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)"

echo "results: ${RUN_ROOT}/results"
