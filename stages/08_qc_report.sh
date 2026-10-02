# shellcheck shell=bash
set -euo pipefail
# --- stage 8: qc_report ---
stage_qc_report() {
    # -f --> overwrite an existing report; without it a rerun writes
    #        multiqc_report_1.html and leaves the old one in place
    multiqc -q -f -o "$RES" "$QC" "$LOG" 2> "${LOG}/multiqc.log"

    [[ -s "${RES}/multiqc_report.html" ]] || die "multiqc produced no report"
    log "QC report written"
}
