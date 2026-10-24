#!/usr/bin/env bash
# the entry script every aws batch job runs: copy the inputs in from s3, run the pipeline, copy results/ back out
# stop on any error, any unset variable, or any failed command in a pipe
set -euo pipefail
# setup: the settings from the job definition, the job's id, an empty folder
# DATA and RESULTS come from the job definition; if either is missing the script stops here with that message
: "${DATA:?set DATA to the s3:// folder that holds samplesheet.csv, the FASTQs and the reference}"
: "${RESULTS:?set RESULTS to the s3:// folder the results go to}"
# REF_NAME defaults to smoke.fa when the job definition does not set it
: "${REF_NAME:=smoke.fa}"
# batch sets AWS_BATCH_JOB_ID for every job; outside batch it falls back to "local"
job=${AWS_BATCH_JOB_ID:-local}
# a fresh, empty temp folder for this run's data and output
work=$(mktemp -d /tmp/run.XXXXXX)

# 1 · copy in
echo "[batch_run] 1/3 copying ${DATA}/ to ${work}/data"
# download everything under DATA: the samplesheet, the fastqs and the reference with its index files
aws s3 cp "${DATA%/}/" "${work}/data/" --recursive --no-progress
# 2 · run
echo "[batch_run] 2/3 running the pipeline: REF=${REF_NAME} REGION=${REGION:-?} THREADS=${THREADS:-?}"
cd "${work}/data"                         # the samplesheet's FASTQ paths are relative to its folder
# run all ten stages with my week-1 driver; REF points at the reference that was just downloaded
REF="${work}/data/${REF_NAME}" bash /pipeline/run_pipeline.sh samplesheet.csv "${work}/out"
# 3 · copy out
echo "[batch_run] 3/3 copying ${work}/out/results/ to ${RESULTS%/}/${job}/"
# upload results/ into a folder named after the job id, so two runs never overwrite each other
aws s3 cp "${work}/out/results/" "${RESULTS%/}/${job}/" --recursive --no-progress
echo "[batch_run] done"