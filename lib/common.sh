# shellcheck shell=bash
set -euo pipefail   # the driver that sources this already set it; repeated so the file stands alone
# lib/common.sh — what every stage needs. Sourced by run_pipeline.sh and
# run_sample.sh, never run by itself.
#
# Week 1 had one driver with everything inside it. Now there are two drivers
# (whole cohort / one sample) calling the same ten stages, so the settings and
# helpers they share live here and the stages live in stages/.

# the repository root (this file is in lib/, so one level up)
PIPE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# messages go to stderr so that a stage's stdout stays free for data
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 65; }

# Configuration. Everything has a default and can be overridden from the
# environment. A Slurm job starts the pipeline with nothing in front of `bash`,
# so the defaults are the Explorer values.
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
# On the cluster the job script exports THREADS from SLURM_CPUS_PER_TASK.
# 4 is only the laptop fallback.
THREADS=${THREADS:-4}

# Output folders, derived from OUT (set by the driver).
setup_dirs() {
    QC="${OUT}/qc_raw"; TRIM="${OUT}/trim"; ALN="${OUT}/align"
    VAR="${OUT}/variants"; LOG="${OUT}/logs"; RES="${OUT}/results"
    mkdir -p "$QC" "$TRIM" "$ALN" "$VAR" "$LOG" "$RES"
}

# rows <samplesheet> [sample_id]
#
# Prints one line per sample with exactly six comma-separated fields:
#   sample_id,condition,replicate,library_type,r1_fastq,r2_fastq
#
# Columns are found BY NAME in the header, not by position. The week-1 smoke
# sheet had six columns; the cohort sheet on Explorer has ten, and
# `read -r id cond rep layout r1 r2` on that puts columns 6-10 into $r2.
# Going through rows() means every stage can keep its six-variable `read`.
#
# With a sample_id it prints only that sample's row, so the same stage code
# runs one sample (array task) or all of them (cohort job).
rows() {
    local sheet=$1 only=${2:-}
    awk -F, -v want="$only" '
        { sub(/\r$/, "") }                       # tolerate Windows line endings
        NR == 1 {
            n = split("sample_id condition replicate library_type r1_fastq r2_fastq", need, " ")
            for (i = 1; i <= NF; i++) col[$i] = i
            for (i = 1; i <= n; i++)
                if (!(need[i] in col)) {
                    print "samplesheet has no column named " need[i] > "/dev/stderr"
                    exit 65
                }
            next
        }
        /^[[:space:]]*$/ { next }                # skip blank lines
        want != "" && $col["sample_id"] != want { next }
        {
            print $col["sample_id"] "," $col["condition"] "," $col["replicate"] "," \
                  $col["library_type"] "," $col["r1_fastq"] "," $col["r2_fastq"]
        }
    ' "$sheet"
}
