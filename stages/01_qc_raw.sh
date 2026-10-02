set -euo pipefail
# --- stage 1: qc_raw ---
# quality report on raw reads
stage_qc_raw() {
    local id cond rep layout r1 r2 base

    while IFS=, read -r id cond rep layout r1 r2; do
        base=$(basename "$r1" .fastq.gz)
        if [[ -s "${LOG}/${id}.qc_raw.done" ]]; then log "$id: qc already done"; continue; fi

        # -q --> quiet mode
        # -o --> output directory
        fastqc -q -o "$QC" "$r1" > "${LOG}/${id}.fastqc.log" 2>&1
        if [[ "$layout" == "paired" ]]; then
            fastqc -q -o "$QC" "$r2" >> "${LOG}/${id}.fastqc.log" 2>&1
        fi

        # fastqc can exit 0 and write nothing
        [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report"
        date -u +%Y-%m-%dT%H:%M:%SZ > "${LOG}/${id}.qc_raw.done"
        log "$id: qc done"
    done < <(rows "$SHEET" "$SAMPLE")
}
