#!/usr/bin/env bash
# -e --> exit immediately if a command exits with a non-zero status
# -u --> treat unset variables as an error and exit immediately
# -o pipefail --> the return value of a pipeline is the status of the last command
set -euo pipefail

REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}

validate() {
    local sheet=$1
    local problems=0
    local seen_id=" "

    echo "Starting validation..." >&2

    # reads csv line by line, skipping the header; IFS --> internal field separator, splits the line into variables
    while IFS=, read -r id cond rep layout r1 r2; do
        
        # check if r1 file is missing or empty
        if [[ ! -s "$r1" ]] || ! gzip -t "$r1"; then
            echo "Error: Sample $id is missing R1 file ($r1)" >&2
            problems=$((problems + 1))
        fi

        # check if r2 file is missing or empty for paired-end samples
        if [[ "$layout" == "paired" ]]; then
            if [[ ! -s "$r2" ]] || ! gzip -t "$r2"; then
                echo "Error: Sample $id is paired but missing R2 file ($r2)" >&2
                problems=$((problems + 1))
            fi
        fi

        # checking to see if string already contains the sample id
        if [[ "$seen_id" == *"$id"* ]]; then
            echo "Error: Duplicate sample ID found: $id" >&2
            problems=$((problems + 1))
        else
            # if id is not found, appending it to empty string
            seen_id=" $seen_id $id "
        fi

    done < <(tail -n +2 "$sheet")

    # exit 65 if any problems were found
    if (( problems > 0 )); then
        echo "Validation failed: $problems problem(s) found" >&2
        exit 65
    else
        echo "Validation passed" >&2
    fi
}

# Capture the arguments provided by the grading script
sheet_input=$1
out_dir=$2
stage_name=$3

# If the requested stage is "validate", run the validate function and hand it the samplesheet
if [[ "$stage_name" == "validate" ]]; then
    validate "$sheet_input"
fi