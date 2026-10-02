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

# $SLURM_SUBMIT_DIR, not $(dirname "$0"): Slurm runs a COPY of this script from
# its own spool folder, so $0 does not point into slurm/. SLURM_SUBMIT_DIR is
# the folder sbatch was typed in, which submit.sh makes sure is slurm/.
if [[ ! -s "${SLURM_SUBMIT_DIR}/conf/slurm.env" ]]; then
    echo "no conf/slurm.env in ${SLURM_SUBMIT_DIR}; submit from slurm/ or use: bash submit.sh" >&2
    exit 78
fi
source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

if [[ ! -s "${PIPELINE_DIR}/run_sample.sh" ]]; then
    echo "no run_sample.sh in ${PIPELINE_DIR}; set PIPELINE_DIR in conf/slurm.env" >&2
    exit 78
fi

# The tools come from my image. Nothing is loaded or activated here: the last
# line of this script runs the pipeline inside the .sif.
if [[ ! -s "${SIF}" ]]; then
    echo "no image at ${SIF}; fetch it first: sbatch pull.sbatch" >&2
    exit 78
fi

# The cores Slurm gave this task, handed to the pipeline. The stages pass
# "$THREADS" to every tool that can use several cores, so --cpus-per-task above
# is the only number to change.
export THREADS="${SLURM_CPUS_PER_TASK}"      # set from Slurm, not typed as a number

# Temporary files on the node's own disk, removed by a trap however the job
# ends. /tmp is shared with every other job on the node, so the folder is named
# after the job id; an rm at the bottom would not run on a cancel or a timeout.
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

# Task N runs the sample on row N, counting from the first row below the
# header: line 1 of the file is the header, so row N is line N + 1.
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")

# An array wider than the sheet gives an empty name here, and a pipeline given
# an empty name can run every stage over nothing and still exit 0. Refuse.
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

# The exact memory high-water mark of this job, from the kernel. MaxRSS is
# sampled every 30 s and can miss a short peak.
CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak (bytes): $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)"
