set -euo pipefail
# --- stage 7: analyze ---

stage_analyze() {
    # -V --> joint genotyped VCF from stage 6
    # -O --> the final filtered output VCF
    # --filter-expression / --filter-name --> label variants with QUAL < 30
    gatk VariantFiltration \
        -R "$REF" \
        -V "${VAR}/cohort.vcf.gz" \
        -O "${VAR}/cohort.filtered.tmp.vcf.gz" \
        -L "$REGION" \
        --filter-expression "QUAL < 30.0" \
        --filter-name "LowQual" \
        --tmp-dir "${TMPDIR:-/tmp}" \
        2> "${LOG}/variantfiltration.log"
    [[ -s "${VAR}/cohort.filtered.tmp.vcf.gz" ]] || die "VariantFiltration produced no VCF"

    mv "${VAR}/cohort.filtered.tmp.vcf.gz.tbi" "${RES}/cohort.filtered.vcf.gz.tbi"
    mv "${VAR}/cohort.filtered.tmp.vcf.gz"     "${RES}/cohort.filtered.vcf.gz"
    log "filtered VCF: ${RES}/cohort.filtered.vcf.gz"
}
