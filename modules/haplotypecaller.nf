// Stage 5 · quantify
process HAPLOTYPECALLER {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam), path(bai)
    path ref
    path ref_index
    path ref_dict

    output:
    path "${meta.id}.g.vcf.gz",     emit: gvcf
    path "${meta.id}.g.vcf.gz.tbi", emit: tbi

    script:
    def xmx = Math.max(task.memory.toGiga() - 1, 1)
    """
    gatk --java-options "-Xmx${xmx}g" HaplotypeCaller \\
        -R ${ref} -I ${bam} -O ${meta.id}.g.vcf.gz -ERC GVCF \\
        -L ${params.region} --native-pair-hmm-threads ${task.cpus}
    """
}
