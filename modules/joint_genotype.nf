// Stage 6 · merge: every sample's GVCF and its index, at once.
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
    def xmx = Math.max(task.memory.toGiga() - 1, 1)
    """
    args=""
    for g in ${gvcfs}; do args="\$args -V \$g"; done
    gatk --java-options "-Xmx${xmx}g" CombineGVCFs -R ${ref} \$args -O combined.g.vcf.gz
    gatk --java-options "-Xmx${xmx}g" GenotypeGVCFs -R ${ref} -V combined.g.vcf.gz -O cohort.vcf.gz
    """
}
