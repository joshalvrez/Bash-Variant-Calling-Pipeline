THE WEEK-1 SMOKE DATASET
========================

A tiny, complete input for the variant-calling pipeline: it is small enough
that all ten stages run on any laptop in about a minute and a half, and it has
a known answer.


WHAT IT IS

The reference is 1,000,000 bases of real GRCh38 (chr19:20,000,000-21,000,000).
The sequence is renamed smoke_1mb so that nothing computed from it can be
mistaken for a result about a real chromosome.

The reads were simulated from that reference with wgsim, which also planted
SNVs and small insertions and deletions in each sample and wrote them down:

    smoke_01   paired-end   100,000 read pairs   about 30x
    smoke_02   paired-end   100,000 read pairs   about 30x
    smoke_03   single-end    60,000 reads        about 9x   (r2_fastq is empty)


WHAT IS IN THIS FOLDER

    samplesheet.csv                 six columns, the same contract as the cohort;
                                    FASTQ paths are relative to this folder
    smoke.fa  smoke.fa.fai          the reference and its samtools index
    smoke.dict                      its GATK sequence dictionary
    smoke.fa.amb .ann .bwt .pac .sa its BWA index
    smoke_0N_R1.fastq.gz            the reads (and _R2 for the two paired samples)
    smoke_0N.truth.txt              the planted variants, one per line, in five
                                    columns: contig, position, reference base,
                                    planted base, and + for heterozygous or - for
                                    homozygous. A heterozygous SNV has an IUPAC
                                    code as the planted base (R = A/G, Y = C/T,
                                    ...); a "-" in the third or fourth column
                                    marks an indel. wgsim writes - in the fifth
                                    column for every deletion, heterozygous or not.


HOW TO RUN YOUR PIPELINE ON IT

Two settings change and nothing else: the reference and the calling region.

    REF     /full/path/to/smoke/smoke.fa
    REGION  smoke_1mb

Run from inside this folder, because the FASTQ paths in samplesheet.csv are
relative to it:

    cd smoke
    bash /path/to/your-repo/run_pipeline.sh samplesheet.csv ~/smoke-out

If your pipeline reads REF and REGION from the environment, set them on the
same line:

    REF=$PWD/smoke.fa REGION=smoke_1mb bash /path/to/your-repo/run_pipeline.sh samplesheet.csv ~/smoke-out

Measured: the course's reference solution runs all ten stages on this folder in
92 seconds on a laptop with 8 GB of memory.


HOW TO CHECK YOUR ANSWER

Every line of smoke_0N.truth.txt whose third and fourth columns are both bases
is a planted SNV. Your pipeline found it if that sample has a non-reference
genotype at that position in your final VCF. The acceptance test counts exactly
this and asks for 80 % of each sample's planted SNVs.


WHAT THIS DATA CANNOT TELL YOU

Anything about real data. The reads are simulated and the reference is not a
chromosome. The real run is the eight-sample cohort, aligned to the whole
GRCh38 on Explorer, in week 2.
