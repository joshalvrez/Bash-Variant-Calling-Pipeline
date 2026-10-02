# shellcheck shell=bash
set -euo pipefail
# --- stage 2: trim ---
# cuts off adapter sequence and low quality ends
stage_trim() {
    local id cond rep layout r1 r2 n w

    # fastp refuses more than 16 worker threads
    w=$(( THREADS > 16 ? 16 : THREADS ))

    while IFS=, read -r id cond rep layout r1 r2; do
        if [[ -s "${TRIM}/${id}_trimmed_R1.fastq.gz" ]]; then log "$id: trim already done"; continue; fi

        # Written under a .tmp name and renamed only after fastp exits 0, so a
        # job killed mid-write never leaves a half file under the real name
        # (the skip above would trust it). The .tmp names still end in
        # .fastq.gz because fastp decides whether to compress from the extension.
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

        # trimming can only remove reads. Zero left means something is wrong.
        n=$(gzip -dc "${TRIM}/${id}.tmp_R1.fastq.gz" | wc -l)
        (( n > 0 )) || die "$id: nothing survived trimming"

        # R2 first: the skip checks R1, so R1 appearing means both are in place
        if [[ "$layout" == "paired" ]]; then
            mv "${TRIM}/${id}.tmp_R2.fastq.gz" "${TRIM}/${id}_trimmed_R2.fastq.gz"
        fi
        mv "${TRIM}/${id}.tmp_R1.fastq.gz" "${TRIM}/${id}_trimmed_R1.fastq.gz"
        log "$id: trimmed to $(( n / 4 )) reads"
    done < <(rows "$SHEET" "$SAMPLE")
}
