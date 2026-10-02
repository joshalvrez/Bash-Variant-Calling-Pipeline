# shellcheck shell=bash
set -euo pipefail
# --- stage 3: align ---
stage_align() {
    local id cond rep layout r1 r2

    while IFS=, read -r id cond rep layout r1 r2; do
        # done if the SAM is there, or if stage 4 already turned it into the
        # final BAM (stage 4 deletes the SAM once it has)
        if [[ -s "${ALN}/${id}.sam" || -s "${ALN}/${id}.dedup.bam" ]]; then
            log "$id: align already done"; continue
        fi

        # -t --> threads; without it bwa uses ONE core however many Slurm reserved
        # -R --> the read group string from the brief
        # bwa streams its output, so it goes to .tmp and is renamed after exit 0
        if [[ "$layout" == "paired" ]]; then
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_trimmed_R1.fastq.gz" "${TRIM}/${id}_trimmed_R2.fastq.gz" \
                > "${ALN}/${id}.sam.tmp" 2> "${LOG}/${id}.bwa.log"
        else
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_trimmed_R1.fastq.gz" \
                > "${ALN}/${id}.sam.tmp" 2> "${LOG}/${id}.bwa.log"
        fi

        # bwa can exit 0 and write only a header, so check there are alignments
        [[ -s "${ALN}/${id}.sam.tmp" ]] || die "$id: bwa mem wrote nothing"
        grep -qv '^@' "${ALN}/${id}.sam.tmp" || die "$id: bwa mem wrote a header but no alignments"
        mv "${ALN}/${id}.sam.tmp" "${ALN}/${id}.sam"
        log "$id: aligned"
    done < <(rows "$SHEET" "$SAMPLE")
}
