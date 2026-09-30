#!/usr/bin/env bash
# -e --> exit immediately if a command exits with a non-zero status
# -u --> treat unset variables as an error and exit immediately
# -o pipefail --> the return value of a pipeline is the status of the last command
set -euo pipefail

# finds script so stage 9 can call the manifest-writing script
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# The samplesheet has SIX columns, in this order:
#   sample_id, condition, replicate, library_type, r1_fastq, r2_fastq
# Every stage reads it with `read -r id cond rep lt r1 r2`, and `read` puts
# anything left over into the LAST variable -- so a sheet with extra columns
# would silently put them all in $r2. If you add columns, read them by name.

# reading CLAs; $1 is the samplesheet, $2 is the output directory, $? --> if missing, stop and print usage message 
SHEET=${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
# if no 3rd argument, default to publish
LAST=${3:-publish}

# Configuration. Everything has a default and can be overridden from the
# environment, so no path is written into the code.
REF=${REF:-/courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa}
REGION=${REGION:-chr20:1-10000000}
THREADS=${THREADS:-4}

# folder variables
QC="${OUT}/qc_raw"; TRIM="${OUT}/trim"; ALN="${OUT}/align"
VAR="${OUT}/variants"; LOG="${OUT}/logs"; RES="${OUT}/results"
mkdir -p "$QC" "$TRIM" "$ALN" "$VAR" "$LOG" "$RES"

# messages go to stderr so that a stage's stdout stays free for data.
log()  { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 65; }

# The ten stages, in the order they run. Each name has a matching function
# below: `validate` -> stage_validate, `align` -> stage_align, and so on.
STAGES=(validate qc_raw trim align postprocess quantify merge analyze qc_report publish)

# Catch a typo in the third argument before running anything.
known=0
for stage in "${STAGES[@]}"; do
    [[ "$stage" == "$LAST" ]] && known=1
done
(( known )) || die "unknown stage: ${LAST}"

# --- stage 0 ----
stage_validate() {
    local id cond rep layout r1 r2 problems=0 n1 n2 r1_ok r2_ok dupes

    # echo messages to command line for troubleshooting 
    echo "Starting validation..." >&2

    # reads csv line by line, skipping the header; IFS --> internal field separator, splits the line into variables
    # places 6 pieces into 6 variables *** 
    while IFS=, read -r id cond rep layout r1 r2; do
        [[ -n "$id" ]] || { log "a row has no sample_id"; problems=$(( problems + 1 )); continue; }

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
    # starting at line 2 --> skips header 
    # < <(...) --> process substitution; feeds output into loop
    done < <(tail -n +2 "$SHEET")

    # duplicate sample ids. sort; uniq -d prints only the repeats.
    dupes=$(awk -F, 'NR>1 { print $1 }' "$SHEET" | sort | uniq -d)
    [[ -z "$dupes" ]] || { log "duplicate sample_id: $dupes"; problems=$(( problems + 1 )); }

    # the reference and its indexes are where the config says they are
    [[ -s "$REF" ]]             || { log "no reference FASTA at ${REF}";              problems=$(( problems + 1 )); }
    [[ -s "${REF}.fai" ]]       || { log "no .fai index at ${REF}.fai";               problems=$(( problems + 1 )); }
    [[ -s "${REF%.*}.dict" ]]   || { log "no sequence dictionary at ${REF%.*}.dict";  problems=$(( problems + 1 )); }
    [[ -s "${REF}.bwt" ]]       || { log "no BWA index at ${REF}.bwt";                problems=$(( problems + 1 )); }

    # exit 65 if any problems were found
    (( problems == 0 )) || die "validation failed with ${problems} problem(s)"
    echo "Validation passed" >&2
}

# --- stage 1 ----
# quality report on raw reads
stage_qc_raw() {
    local id cond rep layout r1 r2 base

    echo "Starting FastQC..." >&2

    # reads csv line by line, skipping the header; IFS --> internal field separator, splits the line into variables
    while IFS=, read -r id cond rep layout r1 r2; do
        # run FastQC on R1 and R2 files, outputting to the specified directory
        # -q --> quiet mode, suppresses output to stdout
        # -o --> output directory
        fastqc -q -o "$QC" "$r1" > "${LOG}/${id}.fastqc.log" 2>&1
        if [[ "$layout" == "paired" ]]; then
            fastqc -q -o "$QC" "$r2" >> "${LOG}/${id}.fastqc.log" 2>&1
        fi

        # fastqc can exit 0 and write nothing, so check the report exists
        base=$(basename "$r1" .fastq.gz)
        [[ -s "${QC}/${base}_fastqc.zip" ]] || die "$id: fastqc produced no report"
        log "$id: qc done"
    done < <(tail -n +2 "$SHEET")

    echo "FastQC completed" >&2
}

# --- stage 2: trim----
# cuts off adapter sequence and low quality ends 
stage_trim() {
    local id cond rep layout r1 r2 n

    echo "Starting Stage 2: fastp trimming..." >&2

    while IFS=, read -r id cond rep layout r1 r2; do

        echo "Trimming sample $id..." >&2

        # run fastp for paired-end or single-end reads
        # -i --> input file for R1
        # -o --> output file for trimmed R1
        # -h --> output HTML report
        if [[ "$layout" == "paired" ]]; then
            fastp \
                -i "$r1" -I "$r2" \
                -o "${TRIM}/${id}_trimmed_R1.fastq.gz" -O "${TRIM}/${id}_trimmed_R2.fastq.gz" \
                -h "${LOG}/${id}_fastp.html" -j "${LOG}/${id}_fastp.json" \
                2> "${LOG}/${id}.fastp.log"
        else
            fastp \
                -i "$r1" \
                -o "${TRIM}/${id}_trimmed_R1.fastq.gz" \
                -h "${LOG}/${id}_fastp.html" -j "${LOG}/${id}_fastp.json" \
                2> "${LOG}/${id}.fastp.log"
        fi

        # trimming can only remove reads. Zero left means something is wrong.
        n=$(gzip -dc "${TRIM}/${id}_trimmed_R1.fastq.gz" | wc -l)
        (( n > 0 )) || die "$id: nothing survived trimming"
        log "$id: trimmed to $(( n / 4 )) reads"

    done < <(tail -n +2 "$SHEET")
}

# --- stage 3: align ----
stage_align() {
    local id cond rep layout r1 r2

    echo "Starting Stage 3: BWA alignment..." >&2

    # reads csv line by line, skipping the header
    while IFS=, read -r id cond rep layout r1 r2; do

        # run BWA mem for paired-end or single-end reads
        # -R requires the exact Read Group string specified in the brief
        # aligning trimmed reads from earlier stage
        if [[ "$layout" == "paired" ]]; then
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_trimmed_R1.fastq.gz" "${TRIM}/${id}_trimmed_R2.fastq.gz" \
                > "${ALN}/${id}.sam" 2> "${LOG}/${id}.bwa.log"
        else
            bwa mem -t "$THREADS" -R "@RG\tID:${id}\tSM:${id}" "$REF" \
                "${TRIM}/${id}_trimmed_R1.fastq.gz" \
                > "${ALN}/${id}.sam" 2> "${LOG}/${id}.bwa.log"
        fi

        # bwa can exit 0 and write only a header, so check there are alignments
        [[ -s "${ALN}/${id}.sam" ]] || die "$id: bwa mem wrote nothing"
        grep -qv '^@' "${ALN}/${id}.sam" || die "$id: bwa mem wrote a header but no alignments"
        log "$id: aligned"

    done < <(tail -n +2 "$SHEET")
}

# --- stage 4: postprocess ----
stage_postprocess() {
    local id cond rep layout r1 r2

    echo "Starting Samtools processing..." >&2

    while IFS=, read -r id cond rep layout r1 r2; do
        # -bS --> input is in SAM format, output is in BAM format
        # -o --> output directory
        samtools view -bS "${ALN}/${id}.sam" > "${ALN}/${id}.bam"
        samtools sort "${ALN}/${id}.bam" -o "${ALN}/${id}_sorted.bam"

        # mark PCR/optical duplicates so HaplotypeCaller ignores them
        gatk MarkDuplicates \
            -I "${ALN}/${id}_sorted.bam" \
            -O "${ALN}/${id}.dedup.bam" \
            -M "${LOG}/${id}.dup_metrics.txt" \
            2> "${LOG}/${id}.markdup.log"
        samtools index "${ALN}/${id}.dedup.bam"

        [[ -s "${ALN}/${id}.dedup.bam" ]] || die "$id: MarkDuplicates produced no BAM"
        log "$id: sorted, duplicates marked, indexed"
    done < <(tail -n +2 "$SHEET")

    echo "Samtools processing completed" >&2
}

# --- stage 5: quantify ----
stage_quantify() {
    local id cond rep layout r1 r2

    echo "Starting Stage 5: GATK HaplotypeCaller..." >&2

    # loop through each sample to call variants
    while IFS=, read -r id cond rep layout r1 r2; do

        echo "Calling variants for $id..." >&2

        # run HaplotypeCaller per sample
        # -R --> reference genome we set at the top of the script
        # -I --> input BAM file (TODO: make sure this name matches the MarkDuplicates output from stage 4!!!!!)
        # -O --> output file for specific sample
        # -L --> restricts calling to our specific region (smoke_1mb or chr20)
        # -ERC GVCF --> tells GATK to output a genomic VCF instead of a regular VCF
        gatk HaplotypeCaller \
            -R "$REF" \
            -I "${ALN}/${id}.dedup.bam" \
            -O "${VAR}/${id}.g.vcf.gz" \
            -L "$REGION" \
            -ERC GVCF \
            2> "${LOG}/${id}.haplotypecaller.log"

        [[ -s "${VAR}/${id}.g.vcf.gz" ]] || die "$id: HaplotypeCaller produced no GVCF"
        log "$id: GVCF written"

    done < <(tail -n +2 "$SHEET")
}

# --- stage 6: merge ----
stage_merge() {
    local id cond rep layout r1 r2

    echo "Starting Stage 6: Joint Genotyping..." >&2

    # build a list of all the gvcf files we just made
    # (an array, not a string, so a sample name with a space stays one argument)
    local gvcf_args=()
    while IFS=, read -r id cond rep layout r1 r2; do
        # append sample's gvcf with a -V flag so GATK can read them all at once
        gvcf_args+=(-V "${VAR}/${id}.g.vcf.gz")
    done < <(tail -n +2 "$SHEET")

    echo "Combining GVCFs..." >&2

    # -R --> reference genome
    # -O --> output file
    # -L --> region to run on
    gatk CombineGVCFs \
        -R "$REF" \
        "${gvcf_args[@]}" \
        -O "${VAR}/cohort.g.vcf.gz" \
        -L "$REGION" \
        2> "${LOG}/combinegvcfs.log"

    [[ -s "${VAR}/cohort.g.vcf.gz" ]] || die "CombineGVCFs produced no cohort GVCF"

    echo "Genotyping cohort..." >&2

    # -V --> merged cohort gvcf we just created in step 2
    gatk GenotypeGVCFs \
        -R "$REF" \
        -V "${VAR}/cohort.g.vcf.gz" \
        -O "${VAR}/cohort.vcf.gz" \
        -L "$REGION" \
        2> "${LOG}/genotypegvcfs.log"

    [[ -s "${VAR}/cohort.vcf.gz" ]] || die "GenotypeGVCFs produced no cohort VCF"
    log "joint genotyping done"
}

# --- stage 7: analyze ----
stage_analyze() {
    echo "Starting Stage 7: Variant filtration..." >&2

    # hard filtering the cohort VCF
    # -R --> reference genome
    # -V --> joint genotyped VCF from stage 6
    # -O --> the final filtered output VCF
    # --filter-expression --> the math logic from class; check notes for more info!!!!
    # --filter-name --> labeling variants
    gatk VariantFiltration \
        -R "$REF" \
        -V "${VAR}/cohort.vcf.gz" \
        -O "${RES}/cohort.filtered.vcf.gz" \
        -L "$REGION" \
        --filter-expression "QUAL < 30.0" \
        --filter-name "LowQual" \
        2> "${LOG}/variantfiltration.log"

    [[ -s "${RES}/cohort.filtered.vcf.gz" ]] || die "VariantFiltration produced no VCF"
    log "filtered VCF: ${RES}/cohort.filtered.vcf.gz"
}

# --- stage 8: qc_report ----
stage_qc_report() {
    echo "Starting Stage 8: MultiQC..." >&2

    # MultiQC needs directory to begni scan
    multiqc -q -o "$RES" "$QC" "$LOG" 2> "${LOG}/multiqc.log"

    [[ -s "${RES}/multiqc_report.html" ]] || die "multiqc produced no report"
    log "QC report written"
}


# --- stage 9: publish ----
stage_publish() {
    echo "Starting Stage 9: Write manifest..." >&2

    # running provided script to log git commit/outputs
    PIPELINE_NAME=variant-calling \
        bash "${HERE}/lib/write_manifest.sh" "$RES" "$SHEET" "$REF" "$REGION"

    [[ -s "${RES}/manifest.json" ]] || die "write_manifest.sh produced no manifest.json"
    log "results in ${RES}:"
    ls -1 "$RES" >&2
}

# --- driver ---
# goes through the list of stages in order and builds each funciton name from stage name 
n=0
for stage in "${STAGES[@]}"; do
    log "===== stage ${n} : ${stage} ====="
    "stage_${stage}"
    [[ "$stage" == "$LAST" ]] && break
    n=$(( n + 1 ))
done
log "done"