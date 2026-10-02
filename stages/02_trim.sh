set -euo pipefail
# --- stage 2: trim ---
# cut off adapter seq and low quality ends
stage_trim() {
    local id cond rep layout r1 r2 n w

    # fastp can't have >16 worker threads
    w=$(( THREADS > 16 ? 16 : THREADS ))

    while IFS=, read -r id cond rep layout r1 r2; do
        if [[ -s "${TRIM}/${id}_trimmed_R1.fastq.gz" ]]; then log "$id: trim already done"; continue; fi

        # written under temp name and renamed after fastp exits 0
        if [[ "$layout" == "paired" ]]; then
            fastp -w "$w" \
                -i "$r1" -I "$r2" \
                -o "${TRIM}/${id}.tmp_R1.fastq.gz" -O "${TRIM}/${id}.tmp_R2.fastq.gz" \
                -h "${LOG}/${id}_fastp.html" -j "${LOG}/${id}_fastp.json" \
                2> "${LOG}/${id}.fastp.log"
        else
            fastp -w "$w" \
                -i "$r1" \
                -o "${TRIM}/${id}.tmp_R1.fastq.gz" \
                -h "${LOG}/${id}_fastp.html" -j "${LOG}/${id}_fastp.json" \
                2> "${LOG}/${id}.fastp.log"
        fi

        # trimming only remove reads
        # if no reads --> something is wrong .
        n=$(gzip -dc "${TRIM}/${id}.tmp_R1.fastq.gz" | wc -l)
        (( n > 0 )) || die "$id: nothing survived trimming"

        # R2 first: the skip checks R1
        # If R1 present -->  both in place
        if [[ "$layout" == "paired" ]]; then
            mv "${TRIM}/${id}.tmp_R2.fastq.gz" "${TRIM}/${id}_trimmed_R2.fastq.gz"
        fi
        mv "${TRIM}/${id}.tmp_R1.fastq.gz" "${TRIM}/${id}_trimmed_R1.fastq.gz"
        log "$id: trimmed to $(( n / 4 )) reads"
    done < <(rows "$SHEET" "$SAMPLE")
}
