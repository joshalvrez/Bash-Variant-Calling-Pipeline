#!/usr/bin/env bash
#=============================================================================
# run_sample.sh — ONE sample, stages 0-5.
#
#   bash run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]
#
# What a Slurm array task runs: the job script picks the sample, this runs the
# pipeline on it, with the same stage functions run_pipeline.sh uses.
#
# It refuses stages 6-9. Those need every sample at once, and one task cannot
# know whether the other seven have finished — a merge run from here would build
# a "cohort" out of one sample, once per task, each overwriting the last.
#=============================================================================
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

SHEET=${1:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
OUT=${2:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
SAMPLE=${3:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
LAST=${4:-quantify}

source "${HERE}/lib/common.sh"

# the guard --> per-sample stages are allowed
PER_SAMPLE=(validate qc_raw trim align postprocess quantify)
known=0
for stage in "${PER_SAMPLE[@]}"; do
    [[ "$stage" == "$LAST" ]] && known=1
done
(( known )) || die "run_sample.sh stops at quantify (stage 5); '${LAST}' needs the whole cohort — use run_pipeline.sh"

[[ -s "$SHEET" ]] || die "no samplesheet: ${SHEET}"
[[ -n "$(rows "$SHEET" "$SAMPLE")" ]] || die "no sample '${SAMPLE}' in ${SHEET}"

setup_dirs
for f in "${HERE}"/stages/*.sh; do source "$f"; done

n=0
for stage in "${PER_SAMPLE[@]}"; do
    log "===== ${SAMPLE} : stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "${SAMPLE}: done"
