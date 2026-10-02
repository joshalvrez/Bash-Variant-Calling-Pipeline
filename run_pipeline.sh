#!/usr/bin/env bash
#=============================================================================
# run_pipeline.sh — every sample, stages 0-9, in order.
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
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # stage 9 writes it into the manifest

SHEET=${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
LAST=${3:-publish}
SAMPLE=""        # empty means "every sample" — see rows() in lib/common.sh

source "${HERE}/lib/common.sh"

# The ten stages, in the order they run. Each name has a matching function in
# stages/: `validate` -> stage_validate, `align` -> stage_align, and so on.
STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

# Catch a typo in the third argument before running anything.
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
