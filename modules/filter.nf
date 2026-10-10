// Stage 7 · analyze: label variants with QUAL < 30, then the variants table.
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
    gatk VariantFiltration \\
        -R ${ref} \\
        -V ${vcf} \\
        -O cohort.filtered.vcf.gz \\
        -L ${params.region} \\
        --filter-expression "QUAL < 30.0" \\
        --filter-name "LowQual"
    make_variants_tsv.sh cohort.filtered.vcf.gz
    """
}
