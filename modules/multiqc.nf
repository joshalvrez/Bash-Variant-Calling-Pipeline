// Stage 8 · qc_report: -f overwrites an existing report.
process MULTIQC {
    container params.containers.multiqc

    input:
    path qc_files

    output:
    path 'multiqc_report.html'

    script:
    """
    multiqc -q -f .
    """
}
