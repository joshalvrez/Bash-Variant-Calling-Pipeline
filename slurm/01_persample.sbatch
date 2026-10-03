#!/bin/bash
#SBATCH --job-name=w2-persample
#SBATCH --array=1-8
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --output=logs/persample_%A_%a.out
#SBATCH --export=NONE
#-----------------------------------------------------------------------------
# Stages 0-5 for ONE sample, as one task of an array.
#
# No analysis happens in this file. It decides WHICH sample runs and with what
# resources; run_sample.sh decides what to do to it.
#
# The three resource lines above were measured, not guessed (RESOURCES.md):
#   --cpus-per-task=4  the knee: 8 cores saved 1:13 over 4 and kept only 2.9 busy
#   --mem=16G          highest peak seen was 13.6 GiB, so the first request stays
#   --time=00:30:00    longest task was 11:06; the first request was 01:00:00
#-----------------------------------------------------------------------------
set -euo pipefail

if [[ ! -s "${SLURM_SUBMIT_DIR}/conf/slurm.env" ]]; then
    echo "no conf/slurm.env in ${SLURM_SUBMIT_DIR}; submit from slurm/ or use: bash submit.sh" >&2
    exit 78
fi
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

if [[ ! -s "${PIPELINE_DIR}/run_sample.sh" ]]; then
    echo "no run_sample.sh in ${PIPELINE_DIR}; set PIPELINE_DIR in conf/slurm.env" >&2
    exit 78
fi

# The tools come from my image --> othing is loaded or activated here.
if [[ ! -s "${SIF}" ]]; then
    echo "no image at ${SIF}; fetch it first: sbatch pull.sbatch" >&2
    exit 78
fi

# the cores Slurm gave this task, handed to the pipeline
export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")

[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }

# For TROUBLESHOOTING.md only: make one chosen task fail on purpose.
#   sbatch --export=FAIL_TASK=2 --array=1-3 01_persample.sbatch
if [[ "${FAIL_TASK:-}" == "${SLURM_ARRAY_TASK_ID}" ]]; then
    echo "task ${SLURM_ARRAY_TASK_ID} (${SAMPLE}): failing on purpose, FAIL_TASK=${FAIL_TASK}" >&2
    exit 1
fi

echo "task ${SLURM_ARRAY_TASK_ID} on $(hostname): ${SAMPLE}, ${SLURM_CPUS_PER_TASK} cores, run root ${RUN_ROOT}"
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
    bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"

CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak (bytes): $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)"
