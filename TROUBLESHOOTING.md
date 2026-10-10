# Troubleshooting: Assignment 4 (Nextflow)

---

## AI acknowledgement

I used Claude Sonnet 5.5 while working on this assignment. During this assignment, Claude assisted me by helping me draft the first versions of `main.nf`, the process files in `modules/`, `bin/validate_samplesheet.sh`, `bin/make_variants_tsv.sh`, `nextflow.config` and `slurm/nextflow.sbatch`, working from the assignment page and course demo. The commands inside the modules are generic bwa and GATK commands that Claude helped me create. The VariantFiltration expression (`QD < 2.0`) is a placeholder which resulted in values that differed from my week 3 assignment. On top of this, Claude helped me breakdown read error outputs from the CLI. Finally, Claude assisted in drafting this file from the output of my runs and I made final edits and changes before submitting. 

## 1. Ctrl-C halfway through a smoke run, then `-resume`

**Command**

```bash
rm -rf work .nextflow* results
nextflow run main.nf -profile docker -resume -ansi-log false \
    --samplesheet $PWD/smoke/samplesheet.csv --ref $PWD/smoke/smoke.fa --region smoke_1mb
# Ctrl-C after BWA_MEM (smoke_01) and BWA_MEM (smoke_02) were submitted,
```

**Output**

First run, before the Ctrl-C: `VALIDATE`, `FASTQC` and `FASTP` for all three samples, and `BWA_MEM` for smoke_01 and smoke_02 had been submitted.

Second run (`-resume`):

- `cached`: VALIDATE, FASTP (smoke_01), FASTP (smoke_02).
- Ran again: FASTP (smoke_03), all three FASTQC, all three BWA_MEM, then everything downstream (MARKDUPLICATES, HAPLOTYPECALLER, JOINT_GENOTYPE, FILTER, MULTIQC, PUBLISH).

then ran the same command again

**Why / fix**

`-resume` reuses a task only if it finished and its script and inputs hash to the same value. Tasks that were still running when I pressed Ctrl-C, or had not started, had no finished outputs, so they ran again.

---

## 2. The reference given as a queue channel in the stage-3 call

**Command**


```groovy
BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)
```

**Output**

No error. The run finished and listed its outputs. BWA_MEM, however, only ran for one sample (smoke_02), not three.

**Why / fix**

`channel.fromPath(...)` makes a queue channel, which holds one item and gets used up. The first sample took the reference, and the other two had nothing left, resulting in their BWA_MEM tasks never running. Nextflow doesn't treat that as an error. `file(params.ref)` makes a value channel, which every sample can read, so I changed the call back to `BWA_MEM(FASTP.out.reads, ref, ref_index)`. The reference and its index files should always be value channels (`file()` and `files()`).

---

## 3. Backslash removed from `\$(...)` in a script block

**Command**

In `modules/markduplicates.nf`, the line

```groovy
echo "markdup finished \$(date)"
```

became

```groovy
echo "markdup finished $(date)"
```

**Output**

Run did not fail. All three MARKDUPLICATES tasks ran and exited 0, and so did the stages after them; however, the task did the wrong thing without saying so. I aimed at an error and got silent wrong output: the module says `echo "markdup finished $(date)"`, the task's `.command.sh` says `echo "markdup finished date)"`, and the task printed `markdup finished date)` instead of a date.

**Evidence from the task folder**

`.command.sh`:

```
#!/bin/bash -euo pipefail
gatk MarkDuplicates -I smoke_01.bam -O smoke_01.md.bam -M smoke_01.md.metrics.txt
samtools index smoke_01.md.bam
echo "markdup finished date)"
```

**Why / fix**

Nextflow reads the `$` in a script block before bash does. Without the backslash, it ate the `$(`, so `.command.sh` only had `date)` in it. Bash never ran `date`. Nothing crashed and the task just printed the wrong thing. To fix this, I placed the backslash back, `\$(date)`. The rule is `${name}` for Nextflow values and `\$` for any `$` that bash should see. Reading `.command.sh` shows what bash actually got.

---

## 4. `time = '2m'` for HAPLOTYPECALLER on the first Explorer run

**Command**

```groovy
withName: 'HAPLOTYPECALLER' {
    time = '2m'
}
```

**Output**
Nextflow reported: `HAPLOTYPECALLER (NA07357)` terminated with an error exit status (140).

| Job | State | Elapsed | Timelimit | ExitCode |
|---|---|---|---|---|
| nf-HAPLOTYPECALLER_(NA07357) | FAILED | 00:01:20 | 00:02:00 | 12:0 |
| nf-HAPLOTYPECALLER_(NA12892) | FAILED | 00:01:18 | 00:02:00 | 12:0 |
| nf-HAPLOTYPECALLER_(NA12891) | FAILED | 00:01:02 | 00:02:00 | 12:0 |
| the other three | CANCELLED+ | 00:00:18 to 00:00:37 | 00:02:00 | 0:0 |

**Why / fix**

Nextflow tells Slurm to warn the job 30 seconds before its time limit (signal USR2), and then Nextflow stops the task itself. So the task died at the warning and  not at the limit. That's why `sacct` said `FAILED` with exit code `12:0`, not `TIMEOUT`, and why Nextflow reported exit status 140. The other three tasks were cancelled when the run stopped. To fix it I put `time = '1h'` back (`git checkout nextflow.config`) and submitted again. `-resume` doesn't care that the time limit changed, so everything that had already finished was reused and the run picked up at HAPLOTYPECALLER.
