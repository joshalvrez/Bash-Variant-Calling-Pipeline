# Bash Variant-Calling Pipeline

BINF 6610 · Fall 2026 · Assignment 1  

A ten-stage germline variant-calling pipeline written in Bash. It takes a samplesheet of FASTQ
files, aligns each sample to a reference genome, calls variants per sample, genotypes the whole
cohort jointly, and writes one hard-filtered cohort VCF plus a `manifest.json` recording what
produced it.

It follows the same architecture as the week-1 RNA-seq demo (samplesheet as the only input,
one function per stage, a check after every tool, progress messages on stderr), applied to a
different question with different tools.

## Stages

| # | Stage | Tool | What it does |
|---|---|---|---|
| 0 | `validate` | bash | Checks the samplesheet, every FASTQ and the reference **before any compute**, and reports every problem together |
| 1 | `qc_raw` | FastQC | QC report on the raw reads |
| 2 | `trim` | fastp | Adapter and quality trimming |
| 3 | `align` | BWA-MEM | Aligns to the reference, with read group `SM` set to the `sample_id` |
| 4 | `postprocess` | samtools, GATK | SAM → BAM, sort, mark duplicates, index |
| 5 | `quantify` | GATK HaplotypeCaller | Per-sample variant calling into a GVCF (`-ERC GVCF`) |
| 6 | `merge` | GATK CombineGVCFs + GenotypeGVCFs | Joint genotyping across every sample |
| 7 | `analyze` | GATK VariantFiltration | Hard filter (`QUAL < 30` → `LowQual`) |
| 8 | `qc_report` | MultiQC | One QC report across the cohort |
| 9 | `publish` | `lib/write_manifest.sh` | Writes `results/manifest.json` |

## Usage

```bash
./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]
```

The optional third argument is the **last stage to run**. Leave it out to run all ten.

```bash
./run_pipeline.sh samplesheet.csv out validate    # stage 0 only
./run_pipeline.sh samplesheet.csv out align       # stages 0–3
./run_pipeline.sh samplesheet.csv out             # all ten
```

### Configuration

Set from the environment, with defaults for the Explorer cluster:

| Variable | Meaning | Default |
|---|---|---|
| `REF` | Reference FASTA (with `.fai`, `.dict` and BWA index beside it) | GRCh38 1000 Genomes analysis set on Explorer |
| `REGION` | Calling region, passed to GATK as `-L` | `chr20:1-10000000` |
| `THREADS` | Threads for BWA | `4` |

### Smoke run (laptop)

Run from inside `smoke/`, since the FASTQ paths in its samplesheet are relative to that folder:

```bash
cd smoke
REF=$PWD/smoke.fa REGION=smoke_1mb bash ../run_pipeline.sh samplesheet.csv ../smoke-out
```

## Samplesheet

Six columns, in this order:

```
sample_id,condition,replicate,library_type,r1_fastq,r2_fastq
```

`library_type` (`paired` or `single`) decides how each sample is handled. A single-end
sample has an empty `r2_fastq`. The pipeline never branches on a sample's name.

## Repository layout

```
run_pipeline.sh          the pipeline: one function per stage, run in order
lib/write_manifest.sh    the course's manifest script (stage 9)
smoke-run/
  cohort.filtered.vcf.gz   stage-7 VCF from the smoke run
  manifest.json            stage-9 manifest from the same run
TROUBLESHOOTING.md       what broke, how I found it, and the fix
```

Sequencing data, reference files, the acceptance tests and run output (`smoke/`, `tests/`,
`smoke-out/`, `results/`) are not committed.

## Requirements

bash, gzip, awk, FastQC, fastp, BWA, samtools, GATK 4, MultiQC.
