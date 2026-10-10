// Stage 2 · trim: adapters and low-quality ends. fastp can't have more than 16 worker threads.
// The branch is on meta.single_end, read from the samplesheet.
process FASTP {
    tag "${meta.id}"
    container params.containers.fastp

    input:
    tuple val(meta), path(reads)

    output:
    tuple val(meta), path('*.trim.fastq.gz'), emit: reads
    path "${meta.id}.fastp.json",              emit: json

    script:
    def w = Math.min(task.cpus, 16)
    if (meta.single_end)
        """
        fastp -w ${w} -i ${reads} -o ${meta.id}_R1.trim.fastq.gz \\
              -h ${meta.id}.fastp.html -j ${meta.id}.fastp.json
        n=\$(gzip -dc ${meta.id}_R1.trim.fastq.gz | wc -l)
        (( n > 0 )) || { echo "${meta.id}: nothing survived trimming" >&2; exit 1; }
        """
    else
        """
        fastp -w ${w} -i ${reads[0]} -I ${reads[1]} \\
              -o ${meta.id}_R1.trim.fastq.gz -O ${meta.id}_R2.trim.fastq.gz \\
              -h ${meta.id}.fastp.html -j ${meta.id}.fastp.json
        n=\$(gzip -dc ${meta.id}_R1.trim.fastq.gz | wc -l)
        (( n > 0 )) || { echo "${meta.id}: nothing survived trimming" >&2; exit 1; }
        """
}
