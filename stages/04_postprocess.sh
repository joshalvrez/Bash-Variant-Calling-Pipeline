# shellcheck shell=bash
set -euo pipefail
# --- stage 4: postprocess ---
# SAM -> BAM -> sorted -> duplicates marked -> indexed
stage_postprocess() {
    local id cond rep layout r1 r2 work

    # Intermediates and sort spill files go on the node's own disk when the job
    # script set TMPDIR; on the laptop they go beside the output as before.
    work="${TMPDIR:-${ALN}}"

    while IFS=, read -r id cond rep layout r1 r2; do
        if [[ -s "${ALN}/${id}.dedup.bam" && -s "${ALN}/${id}.dedup.bam.bai" ]]; then
            log "$id: postprocess already done"; continue
        fi

        # -bS --> input is SAM, output is BAM
        samtools view -@ "$THREADS" -bS "${ALN}/${id}.sam" > "${work}/${id}.unsorted.bam"
        # -T --> where sort writes its temporary files (default is beside the
        #        output, which on the cluster is /scratch, over the network)
        samtools sort -@ "$THREADS" -T "${work}/sort.${id}" \
            -o "${work}/${id}.sorted.bam" "${work}/${id}.unsorted.bam"

        # mark PCR/optical duplicates so HaplotypeCaller ignores them.
        # Output name ends in .tmp.bam (not .bam.tmp): the format is chosen from
        # the extension.
        gatk MarkDuplicates \
            -I "${work}/${id}.sorted.bam" \
            -O "${ALN}/${id}.dedup.tmp.bam" \
            -M "${LOG}/${id}.dup_metrics.txt" \
            --TMP_DIR "${TMPDIR:-/tmp}" \
            2> "${LOG}/${id}.markdup.log"
        [[ -s "${ALN}/${id}.dedup.tmp.bam" ]] || die "$id: MarkDuplicates produced no BAM"
        samtools index -@ "$THREADS" "${ALN}/${id}.dedup.tmp.bam"

        # real names appear only now, after every tool exited 0
        mv "${ALN}/${id}.dedup.tmp.bam.bai" "${ALN}/${id}.dedup.bam.bai"
        mv "${ALN}/${id}.dedup.tmp.bam"     "${ALN}/${id}.dedup.bam"

        # the intermediates are not needed again
        rm -f "${work}/${id}.unsorted.bam" "${work}/${id}.sorted.bam" "${ALN}/${id}.sam"
        log "$id: sorted, duplicates marked, indexed"
    done < <(rows "$SHEET" "$SAMPLE")
}
