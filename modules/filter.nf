// Stage 7 · analyze. The one filter is a placeholder; use your week-3 filters.
process FILTER {
    container params.containers.gatk

    input:
    path vcf
    path vcf_index
    path ref
    path ref_index
    path ref_dict

    output:
    path 'cohort.filtered.vcf.gz', emit: vcf
    path 'variants.tsv',           emit: table

    script:
    """
    gatk VariantFiltration -R ${ref} -V ${vcf} -O cohort.filtered.vcf.gz \\
        --filter-expression "QD < 2.0" --filter-name "LowQD"
    make_variants_tsv.sh cohort.filtered.vcf.gz
    """
}
