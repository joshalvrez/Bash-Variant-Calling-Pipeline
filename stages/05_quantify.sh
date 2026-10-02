set -euo pipefail
# --- stage 5: quantify ---
# per-sample variant calling -> one GVCF per sample
stage_quantify() {
    local id cond rep layout r1 r2

    while IFS=, read -r id cond rep layout r1 r2; do
        if [[ -s "${VAR}/${id}.g.vcf.gz" && -s "${VAR}/${id}.g.vcf.gz.tbi" ]]; then
            log "$id: GVCF already done"; continue
        fi

        # -R --> reference genome
        # -I --> MarkDuplicates output from stage 4
        # -L --> restricts calling to our region
        # -ERC GVCF --> genomic VCF
        gatk HaplotypeCaller \
            -R "$REF" \
            -I "${ALN}/${id}.dedup.bam" \
            -O "${VAR}/${id}.tmp.g.vcf.gz" \
            -L "$REGION" \
            -ERC GVCF \
            --native-pair-hmm-threads "$THREADS" \
            --tmp-dir "${TMPDIR:-/tmp}" \
            2> "${LOG}/${id}.haplotypecaller.log"

        [[ -s "${VAR}/${id}.tmp.g.vcf.gz" ]] || die "$id: HaplotypeCaller produced no GVCF"
        mv "${VAR}/${id}.tmp.g.vcf.gz.tbi" "${VAR}/${id}.g.vcf.gz.tbi"
        mv "${VAR}/${id}.tmp.g.vcf.gz"     "${VAR}/${id}.g.vcf.gz"
        log "$id: GVCF written"
    done < <(rows "$SHEET" "$SAMPLE")
}
