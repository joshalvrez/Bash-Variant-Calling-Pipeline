// Stage 4 · postprocess
process MARKDUPLICATES {
    tag "${meta.id}"
    container params.containers.gatk

    input:
    tuple val(meta), path(bam)

    output:
    tuple val(meta), path("${meta.id}.md.bam"), path("${meta.id}.md.bam.bai")

    script:
    """
    gatk MarkDuplicates -I ${bam} -O ${meta.id}.md.bam -M ${meta.id}.md.metrics.txt
    samtools index ${meta.id}.md.bam
    echo "markdup finished \$(date)"
    """
}
