// Stage 3 · align: bwa mem into a SAM, then check it has alignments.
process BWA_MEM {
    tag "${meta.id}"
    container params.containers.bwa

    input:
    tuple val(meta), path(reads)
    path ref
    path ref_index

    output:
    tuple val(meta), path("${meta.id}.sam")

    script:
    """
    bwa mem -t ${task.cpus} -R '@RG\\tID:${meta.id}\\tSM:${meta.id}' ${ref} ${reads} > ${meta.id}.sam
    [[ -s ${meta.id}.sam ]] || { echo "${meta.id}: bwa mem wrote nothing" >&2; exit 1; }
    grep -qv '^@' ${meta.id}.sam || { echo "${meta.id}: bwa mem wrote a header but no alignments" >&2; exit 1; }
    """
}
