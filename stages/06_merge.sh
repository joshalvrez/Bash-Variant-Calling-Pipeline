# shellcheck shell=bash
set -euo pipefail
# --- stage 6: merge ---
# joint genotyping across the whole cohort.
#
# THIS STAGE NEEDS EVERY SAMPLE. In week 1 that was true because the loop above
# it had finished. On the cluster the samples are separate array tasks, so the
# cohort job is submitted with --dependency=afterok and this stage also checks
# for itself that every GVCF is there.
stage_merge() {
    local id cond rep layout r1 r2 work
    local gvcf_args=()

    while IFS=, read -r id cond rep layout r1 r2; do
        # without this, a missing sample is silently a missing column
        [[ -s "${VAR}/${id}.g.vcf.gz" ]] || die "no GVCF for ${id}; stage 5 did not finish for it"
        gvcf_args+=(-V "${VAR}/${id}.g.vcf.gz")
    done < <(rows "$SHEET")
    (( ${#gvcf_args[@]} > 0 )) || die "no samples to merge"

    # the combined GVCF is only an intermediate, so it goes on the node's disk
    # when there is one (the job's trap removes it)
    work="${TMPDIR:-${VAR}}"

    log "combining $(( ${#gvcf_args[@]} / 2 )) GVCFs"
    gatk CombineGVCFs \
        -R "$REF" \
        "${gvcf_args[@]}" \
        -O "${work}/cohort.g.vcf.gz" \
        -L "$REGION" \
        --tmp-dir "${TMPDIR:-/tmp}" \
        2> "${LOG}/combinegvcfs.log"
    [[ -s "${work}/cohort.g.vcf.gz" ]] || die "CombineGVCFs produced no cohort GVCF"

    log "genotyping cohort"
    gatk GenotypeGVCFs \
        -R "$REF" \
        -V "${work}/cohort.g.vcf.gz" \
        -O "${VAR}/cohort.tmp.vcf.gz" \
        -L "$REGION" \
        --tmp-dir "${TMPDIR:-/tmp}" \
        2> "${LOG}/genotypegvcfs.log"
    [[ -s "${VAR}/cohort.tmp.vcf.gz" ]] || die "GenotypeGVCFs produced no cohort VCF"

    mv "${VAR}/cohort.tmp.vcf.gz.tbi" "${VAR}/cohort.vcf.gz.tbi"
    mv "${VAR}/cohort.tmp.vcf.gz"     "${VAR}/cohort.vcf.gz"
    rm -f "${work}/cohort.g.vcf.gz" "${work}/cohort.g.vcf.gz.tbi"
    log "joint genotyping done"
}
