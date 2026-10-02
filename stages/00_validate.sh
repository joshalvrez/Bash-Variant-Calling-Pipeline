# shellcheck shell=bash
set -euo pipefail
# --- stage 0: validate ---
# check everything before computing anything
stage_validate() {
    local id cond rep layout r1 r2 problems=0 before n1 n2 r1_ok r2_ok dupes

    while IFS=, read -r id cond rep layout r1 r2; do
        [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }

        # The array task already read this sample's FASTQ files end to end. The
        # cohort job starts again from stage 0, so without this marker it would
        # re-read all eight samples for nothing.
        if [[ -s "${LOG}/${id}.validated" ]]; then log "$id: inputs already verified"; continue; fi
        before=$problems

        # check if r1 file is missing or empty
        [[ -s "$r1" ]] || { log "$id: R1 missing or empty: $r1"; problems=$(( problems + 1 )); }

        # check if r2 file is missing or empty for paired-end samples
        if [[ "$layout" == "paired" ]]; then
            if [[ -z "$r2" ]]; then
                log "$id: r2_fastq is empty but library_type says paired"
                problems=$(( problems + 1 ))
            elif [[ ! -s "$r2" ]]; then
                log "$id: declared paired but R2 is missing or empty: $r2"
                problems=$(( problems + 1 ))
            fi
        fi

        r1_ok=0 r2_ok=0
        if [[ -s "$r1" ]]; then
            if gzip -t "$r1" 2>/dev/null; then r1_ok=1
            else log "$id: R1 is not a valid gzip file (truncated?): $r1"; problems=$(( problems + 1 )); fi
        fi
        if [[ "$layout" == "paired" && -s "$r2" ]]; then
            if gzip -t "$r2" 2>/dev/null; then r2_ok=1
            else log "$id: R2 is not a valid gzip file (truncated?): $r2"; problems=$(( problems + 1 )); fi
        fi

        # the records are whole (4 lines each), and the mates agree
        if (( r1_ok )); then
            n1=$(gzip -dc "$r1" | wc -l)
            (( n1 % 4 == 0 )) || { log "$id: R1 has $n1 lines, not a whole number of records"
                                   problems=$(( problems + 1 )); }
            if (( r2_ok )); then
                n2=$(gzip -dc "$r2" | wc -l)
                (( n1 == n2 )) || { log "$id: R1 has $(( n1 / 4 )) reads, R2 has $(( n2 / 4 ))"
                                    problems=$(( problems + 1 )); }
            fi
        fi

        # Write the marker only if THIS sample raised nothing. It has content
        # (a date) because the check above is -s, which is false for an empty file.
        if (( problems == before )); then
            date -u +%Y-%m-%dT%H:%M:%SZ > "${LOG}/${id}.validated"
            log "$id: inputs verified"
        fi
    done < <(rows "$SHEET" "$SAMPLE")

    # duplicate sample ids, checked over the WHOLE sheet even for one sample
    dupes=$(rows "$SHEET" | cut -d, -f1 | sort | uniq -d)
    [[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }

    # the reference and its indexes are where the config says they are
    [[ -s "$REF" ]]             || { log "no reference FASTA at ${REF}";              problems=$(( problems + 1 )); }
    [[ -s "${REF}.fai" ]]       || { log "no .fai index at ${REF}.fai";               problems=$(( problems + 1 )); }
    [[ -s "${REF%.*}.dict" ]]   || { log "no sequence dictionary at ${REF%.*}.dict";  problems=$(( problems + 1 )); }
    [[ -s "${REF}.bwt" ]]       || { log "no BWA index at ${REF}.bwt";                problems=$(( problems + 1 )); }

    # exit 65 if any problems were found
    (( problems == 0 )) || die "validation failed with ${problems} problem(s)"
    log "validation passed"
}
