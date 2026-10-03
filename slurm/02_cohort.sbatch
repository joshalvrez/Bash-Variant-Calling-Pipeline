#!/bin/bash
#SBATCH --job-name=w2-cohort
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --output=logs/cohort_%j.out
#SBATCH --export=NONE
set -euo pipefail

if [[ ! -s "${SLURM_SUBMIT_DIR}/conf/slurm.env" ]]; then
    echo "no conf/slurm.env in ${SLURM_SUBMIT_DIR}; submit from slurm/ or use: bash submit.sh" >&2
    exit 78
fi
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

if [[ ! -s "${PIPELINE_DIR}/run_pipeline.sh" ]]; then
    echo "no run_pipeline.sh in ${PIPELINE_DIR}; set PIPELINE_DIR in conf/slurm.env" >&2
    exit 78
fi

if [[ ! -s "${SIF}" ]]; then
    echo "no image at ${SIF}; fetch it first: sbatch pull.sbatch" >&2
    exit 78
fi

export THREADS="${SLURM_CPUS_PER_TASK}"

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
