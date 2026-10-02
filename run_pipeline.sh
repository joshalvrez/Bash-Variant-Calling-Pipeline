#!/usr/bin/env bash
#=============================================================================
# run_pipeline.sh — the whole cohort, ten stages, in order.
#
#   bash run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]
#
# The laptop driver, and what the cohort job runs on the cluster. For ONE
# sample (an array task) use run_sample.sh — it calls the same stage functions.
#=============================================================================
# -e --> exit immediately if a command exits with a non-zero status
# -u --> treat unset variables as an error and exit immediately
# -o pipefail --> a pipeline fails if any command in it fails
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

SHEET=${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
LAST=${3:-publish}
# empty means "every sample"
SAMPLE=""

source "${HERE}/lib/common.sh"

# ten stages, in the order they run. each name has a matching function in stages
STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

# catches typo in third argument before running
known=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$LAST" ]] && known=1
done
(( known )) || die "unknown stage: ${LAST}"

[[ -s "$SHEET" ]] || die "no samplesheet: ${SHEET}"
[[ -n "$(rows "$SHEET")" ]] || die "no samples in ${SHEET}"

setup_dirs
for f in "${HERE}"/stages/*.sh; do source "$f"; done

n=0
for stage in "${STAGES[@]}"; do
    log "===== stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "done"
