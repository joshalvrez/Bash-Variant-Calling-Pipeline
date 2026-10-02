set -euo pipefail
# --- stage 9: publish ---
stage_publish() {
    PIPELINE_NAME=variant-calling \
        bash "${PIPE_DIR}/lib/write_manifest.sh" "$RES" "$SHEET" "$REF" "$REGION"

    [[ -s "${RES}/manifest.json" ]] || die "write_manifest.sh produced no manifest.json"
    log "results in ${RES}:"
    ls -1 "$RES" >&2
}
