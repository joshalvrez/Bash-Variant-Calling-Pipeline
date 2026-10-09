#!/usr/bin/env bash
# Stage 0. Replace/extend with your week-1 checks. FASTQs are opened by file NAME.
set -euo pipefail
sheet="$1"; ref="$2"
for f in "${ref}" "${ref}.fai" "${ref%.*}.dict"; do
    [[ -s "$f" ]] || { echo "missing reference file: $f" >&2; exit 1; }
done
while read -r id lt r1 r2; do
    for p in "$r1" "$r2"; do
        [[ -z "$p" ]] && continue
        f=$(basename "$p")
        [[ -s "$f" ]] || { echo "missing FASTQ for $id: $f" >&2; exit 1; }
        gzip -t "$f"
    done
done < <(awk -F, 'NR==1 { for (i=1;i<=NF;i++) c[$i]=i; next }
                  { print $c["sample_id"], $c["library_type"], $c["r1_fastq"], $c["r2_fastq"] }' "$sheet")
echo "samplesheet ok"
