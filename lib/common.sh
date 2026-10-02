set -euo pipefail   
# --- driver ---
# repeated so the file stands alone lib/common.sh — what every stage needs
# run_sample.sh, never run by itself. 

PIPE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# messages go to stderr so that a stage's stdout stays free for data
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { printf 'error: %s\n' "$*" >&2; exit 65; }

REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}

# output folders
setup_dirs() {
    QC="${OUT}/qc_raw"; TRIM="${OUT}/trim"; ALN="${OUT}/align"
    VAR="${OUT}/variants"; LOG="${OUT}/logs"; RES="${OUT}/results"
    mkdir -p "$QC" "$TRIM" "$ALN" "$VAR" "$LOG" "$RES"
}

# rows <samplesheet> [sample_id]
# Prints one line per sample with exactly six comma-separated fields: sample_id,condition,replicate,library_type,r1_fastq,r2_fastq
# Columns are found BY NAME in the header, not by position. 
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
