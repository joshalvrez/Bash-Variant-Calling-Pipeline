// Stage 4 · postprocess: SAM -> BAM -> sorted -> duplicates marked -> indexed.
process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(sam)

    output:
    tuple val(meta), path("${meta.id}.dedup.bam"), path("${meta.id}.dedup.bam.bai"), emit: bam
    path "${meta.id}.dup_metrics.txt",                                              emit: metrics

    script:
    """
    samtools view -@ ${task.cpus} -bS ${sam} > ${meta.id}.unsorted.bam
    samtools sort -@ ${task.cpus} -T sort.${meta.id} -o ${meta.id}.sorted.bam ${meta.id}.unsorted.bam
    gatk MarkDuplicates -I ${meta.id}.sorted.bam -O ${meta.id}.dedup.bam -M ${meta.id}.dup_metrics.txt
    samtools index -@ ${task.cpus} ${meta.id}.dedup.bam
    """
}
