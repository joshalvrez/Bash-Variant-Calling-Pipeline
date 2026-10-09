include { VALIDATE } from './modules/validate'

workflow {
    main:
    ref       = file(params.ref)
    ref_index = files("${params.ref}.*")
    ref_dict  = file("${ref.parent}/${ref.baseName}.dict")
    sheet     = file(params.samplesheet)

    // One item per sample: [meta, reads], with meta = [id: ..., single_end: ...].
    ch_samples = channel.fromPath(sheet)
        .splitCsv(header: true)
        .map { row ->
            def meta = [id: row.sample_id, single_end: row.library_type == 'single']
            def r1 = sheet.parent.resolve(row.r1_fastq)
            def reads = meta.single_end ? [r1] : [r1, sheet.parent.resolve(row.r2_fastq)]
            [meta, reads]
        }
    ch_samples.view { meta, reads -> "sample: ${meta} ${reads*.name}" }

    // Stage 0 gets every FASTQ; each sample will wait for it.
    VALIDATE(sheet, ch_samples.map { _meta, reads -> reads }.collect(), ref, ref_index, ref_dict)
    ch_checked = ch_samples
        .combine(VALIDATE.out.sheet)
        .map { meta, reads, _validated -> [meta, reads] }
    ch_checked.view { meta, _reads -> "checked: ${meta.id}" }
}
