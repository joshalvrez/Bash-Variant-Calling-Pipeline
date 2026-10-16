configfile: "config.yaml"

KNOWN = {"samplesheet", "ref", "region", "outdir", "platform", "executor", "containers"}
unknown = sorted(set(config) - KNOWN)
if unknown:
    raise ValueError(f"unknown config key(s): {', '.join(unknown)}")

import csv
import os
import re

PIPELINE = {"name": "variant-call", "version": "1.0.0"}
OUT = config["outdir"]
BIN = os.path.join(workflow.basedir, "bin")       # bin/ is not on the PATH: call scripts by their path
IMAGES = {name: f"docker://{image}" for name, image in config["containers"].items()}

REF = config["ref"]                                                     # the FASTA
REF_FAI = REF + ".fai"
REF_BWA = [REF + ext for ext in (".amb", ".ann", ".bwt", ".pac", ".sa")]  # bwa's index
REF_DICT = os.path.splitext(REF)[0] + ".dict"                           # smoke.dict, not smoke.fa.dict

SHEET = config["samplesheet"]
with open(SHEET) as fh:
    ROWS = list(csv.DictReader(fh))
SAMPLES = [row["sample_id"] for row in ROWS]
PAIRED = [row["sample_id"] for row in ROWS if row["library_type"] == "paired"]
SINGLE = [row["sample_id"] for row in ROWS if row["library_type"] == "single"]


def resolve(path):
    return path if os.path.isabs(path) else os.path.join(os.path.dirname(SHEET), path)


READS = {
    row["sample_id"]: [resolve(row["r1_fastq"])]
    + ([resolve(row["r2_fastq"])] if row["library_type"] == "paired" else [])
    for row in ROWS
}


def one_of(names):
    """A wildcard pattern matching exactly these sample names, or nothing at all."""
    return "|".join(map(re.escape, names)) if names else "(?!)"

rule all:
    input:
        f"{OUT}/cohort.filtered.vcf.gz",
        f"{OUT}/variants.tsv",
        f"{OUT}/multiqc_report.html",
        f"{OUT}/samples.tsv",
        f"{OUT}/manifest.json",


rule validate:
    input:
        sheet=SHEET,
        fastqs=[fq for reads in READS.values() for fq in reads],
        ref=REF,
        ref_index=[REF_FAI] + REF_BWA,
        ref_dict=REF_DICT,
    output:
        "work/validate/samplesheet.csv",
    log:
        "logs/validate.log",
    container: IMAGES["tools"]
    shell:
        "({BIN}/validate_samplesheet.sh {input.sheet} {input.ref} && cp {input.sheet} {output}) 2> {log}"


# stage 1 · qc_raw — FastQC on the reads as they arrived.
rule fastqc:
    input:
        reads=lambda wc: READS[wc.sample],
        checked=rules.validate.output,
    output:
        directory("work/fastqc/{sample}"),
    log:
        "logs/fastqc/{sample}.log",
    container: IMAGES["fastqc"]
    shell:
        "(mkdir -p {output} && fastqc -q -o {output} {input.reads}"
        " && ls {output}/*_fastqc.zip > /dev/null) 2> {log}"


# stage 2 · trim. Two rules, because a paired sample makes two trimmed files
# and a single-end sample makes one.
rule fastp_paired:
    input:
        r1=lambda wc: READS[wc.sample][0],
        r2=lambda wc: READS[wc.sample][1],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        r2="work/trim/{sample}_R2.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(PAIRED),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        """
        (fastp -w {threads} -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2} \
            -h {output.html} -j {output.json}
        n=$(gzip -dc {output.r1} | wc -l)
        (( n > 0 )) || {{ echo "{wildcards.sample}: nothing survived trimming"; exit 1; }}) 2> {log}
        """


rule fastp_single:
    input:
        r1=lambda wc: READS[wc.sample][0],
        checked=rules.validate.output,
    output:
        r1="work/trim/{sample}_R1.trim.fastq.gz",
        json="work/trim/{sample}.fastp.json",
        html="work/trim/{sample}.fastp.html",
    wildcard_constraints:
        sample=one_of(SINGLE),
    threads: 4
    log:
        "logs/fastp/{sample}.log",
    container: IMAGES["fastp"]
    shell:
        """
        (fastp -w {threads} -i {input.r1} -o {output.r1} -h {output.html} -j {output.json}
        n=$(gzip -dc {output.r1} | wc -l)
        (( n > 0 )) || {{ echo "{wildcards.sample}: nothing survived trimming"; exit 1; }}) 2> {log}
        """

# Stage 3 input: one trimmed file for single-end, two for paired.
def trimmed(wildcards):
    s = wildcards.sample
    if s in PAIRED:
        return [f"work/trim/{s}_R1.trim.fastq.gz", f"work/trim/{s}_R2.trim.fastq.gz"]
    return [f"work/trim/{s}_R1.trim.fastq.gz"]


# Stage 3 · align — bwa mem straight into a sorted BAM.
rule bwa_mem:
    input:
        reads=trimmed,
        ref=REF,
        index=REF_BWA,
    output:
        bam="work/align/{sample}.bam",
    threads: 4
    log:
        "logs/bwa_mem/{sample}.log",
    container: IMAGES["bwa"]
    shell:
        r"""
        (bwa mem -t {threads} -R '@RG\tID:{wildcards.sample}\tSM:{wildcards.sample}' {input.ref} {input.reads} \
            | samtools sort -@ {threads} -T {resources.tmpdir}/sort.{wildcards.sample} -o {output.bam} -
        [ "$(samtools view -c {output.bam})" -gt 0 ] || {{ echo "{wildcards.sample}: bwa mem wrote no alignments"; exit 1; }}) 2> {log}
        """


# Stage 4 · postprocess — mark duplicates, then index.
rule markduplicates:
    input:
        bam="work/align/{sample}.bam",
    output:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        metrics="work/dedup/{sample}.dup_metrics.txt",
    threads: 4
    log:
        "logs/markduplicates/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        """
        (gatk MarkDuplicates -I {input.bam} -O {output.bam} -M {output.metrics} --TMP_DIR {resources.tmpdir}
        samtools index -@ {threads} {output.bam} {output.bai}) 2> {log}
        """


# Stage 5 · quantify — one GVCF per sample.
rule haplotypecaller:
    input:
        bam="work/dedup/{sample}.dedup.bam",
        bai="work/dedup/{sample}.dedup.bam.bai",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        gvcf="work/gvcf/{sample}.g.vcf.gz",
        tbi="work/gvcf/{sample}.g.vcf.gz.tbi",
    params:
        region=config["region"],
    threads: 4
    log:
        "logs/haplotypecaller/{sample}.log",
    container: IMAGES["gatk"]
    shell:
        """
        gatk HaplotypeCaller -R {input.ref} -I {input.bam} -O {output.gvcf} -L {params.region} \
            -ERC GVCF --native-pair-hmm-threads {threads} --tmp-dir {resources.tmpdir} 2> {log}
        """

# Stage 6 · merge — joint genotyping across the cohort.
# expand() lists one GVCF per sample, so this rule waits for every sample.
rule joint_genotype:
    input:
        gvcfs=expand("work/gvcf/{sample}.g.vcf.gz", sample=SAMPLES),
        tbis=expand("work/gvcf/{sample}.g.vcf.gz.tbi", sample=SAMPLES),
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
    params:
        variants=lambda wc, input: " ".join(f"-V {g}" for g in input.gvcfs),
        region=config["region"],
    log:
        "logs/joint_genotype.log",
    container: IMAGES["gatk"]
    shell:
        """
        (gatk CombineGVCFs -R {input.ref} {params.variants} -O work/joint/cohort.g.vcf.gz \
            -L {params.region} --tmp-dir {resources.tmpdir}
        gatk GenotypeGVCFs -R {input.ref} -V work/joint/cohort.g.vcf.gz -O {output.vcf} \
            -L {params.region} --tmp-dir {resources.tmpdir}
        rm -f work/joint/cohort.g.vcf.gz work/joint/cohort.g.vcf.gz.tbi) 2> {log}
        """


# Stage 7 · analyze — filter the cohort VCF and write the variants table.
rule filter:
    input:
        vcf="work/joint/cohort.vcf.gz",
        tbi="work/joint/cohort.vcf.gz.tbi",
        ref=REF,
        fai=REF_FAI,
        dict=REF_DICT,
    output:
        vcf=f"{OUT}/cohort.filtered.vcf.gz",
        tbi=f"{OUT}/cohort.filtered.vcf.gz.tbi",
        table=f"{OUT}/variants.tsv",
    params:
        region=config["region"],
    log:
        "logs/filter.log",
    container: IMAGES["gatk"]
    shell:
        r"""
        (gatk VariantFiltration -R {input.ref} -V {input.vcf} -O {output.vcf} -L {params.region} \
            --filter-expression "QUAL < 30.0" --filter-name "LowQual" --tmp-dir {resources.tmpdir}
        printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > {output.table}
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' {output.vcf} >> {output.table}) 2> {log}
        """


# Stage 8 · qc_report — one MultiQC report, given the reports and not "."
rule multiqc:
    input:
        expand("work/fastqc/{sample}", sample=SAMPLES),
        expand("work/trim/{sample}.fastp.json", sample=SAMPLES),
        expand("work/dedup/{sample}.dup_metrics.txt", sample=SAMPLES),
    output:
        f"{OUT}/multiqc_report.html",
    log:
        "logs/multiqc.log",
    container: IMAGES["multiqc"]
    shell:
        "(multiqc -q -f -o work/multiqc {input} && cp work/multiqc/multiqc_report.html {output}) 2> {log}"


# Stage 9 · publish — the course's rules/publish.smk, unchanged.
PUBLISH_SHEET = rules.validate.output
PUBLISH_RESULTS = [*rules.filter.output, *rules.multiqc.output]
include: "rules/publish.smk"



