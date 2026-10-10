// Stage 6 · merge: joint genotyping across the whole cohort (every GVCF and its index, at once).
process JOINT_GENOTYPE {
    container params.containers.gatk

    input:
    path gvcfs
    path tbis
    path ref
    path ref_index
    path ref_dict

    output:
    path 'cohort.vcf.gz',     emit: vcf
    path 'cohort.vcf.gz.tbi', emit: tbi

    script:
    """
    args=""
    for g in ${gvcfs}; do args="\$args -V \$g"; done
    gatk CombineGVCFs -R ${ref} \$args -O cohort.g.vcf.gz -L ${params.region}
    gatk GenotypeGVCFs -R ${ref} -V cohort.g.vcf.gz -O cohort.vcf.gz -L ${params.region}
    """
}
