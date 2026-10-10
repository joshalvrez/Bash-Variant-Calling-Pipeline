# Troubleshooting: Assignment 4 (Nextflow)

Four failures caused on purpose. Each one: the command, what printed, and the fix.
Last week's four are in the Git history.

---

## 1. Ctrl-C halfway through a smoke run, then `-resume`

**Command**

```bash
rm -rf work .nextflow* results
nextflow run main.nf -profile docker -resume -ansi-log false \
    --samplesheet $PWD/smoke/samplesheet.csv --ref $PWD/smoke/smoke.fa --region smoke_1mb
# Ctrl-C after BWA_MEM (smoke_01) and BWA_MEM (smoke_02) were submitted,
# then the identical command again
```

**What printed**

First run, before the Ctrl-C: `VALIDATE`, `FASTQC` and `FASTP` for all three samples, and `BWA_MEM` for smoke_01 and smoke_02 had been submitted.

Second run (`-resume`):

- `cached`: VALIDATE, FASTP (smoke_01), FASTP (smoke_02).
- Ran again: FASTP (smoke_03), all three FASTQC, all three BWA_MEM, then everything downstream (MARKDUPLICATES, HAPLOTYPECALLER, JOINT_GENOTYPE, FILTER, MULTIQC, PUBLISH).

**Why / fix**

`-resume` reuses a task only if it finished and its script and inputs hash to the same value. Tasks that were still running when I pressed Ctrl-C, or had not started, had no finished outputs, so they ran again. Nothing needs fixing: put `-resume` on every run.

---

## 2. The reference given as a queue channel in the stage-3 call

**Command**

Only in the call to BWA_MEM, `ref` replaced by `channel.fromPath(params.ref)`:

```groovy
BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)
```

then the smoke dataset on the laptop with `-profile docker`.

**What printed**

No error. The run finished and listed its outputs. But BWA_MEM ran for one sample only (smoke_02), not three. smoke_01 and smoke_03 were never aligned, so the VCF held one sample's calls.

**Why / fix**

`channel.fromPath(...)` is a queue channel with one item, and a queue channel is consumed: the first sample that pairs with it uses it up, and the other two samples have nothing to pair with, so their tasks never start. Nextflow does not treat that as an error. `file(params.ref)` is a value channel, which every sample can read, so I put the call back to `BWA_MEM(FASTP.out.reads, ref, ref_index)`. The reference, its `.fai`, `.dict` and BWA index must be value channels, built with `file()` and `files()`. A check is the task count in the progress line: three samples should give three BWA_MEM tasks.

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

then the smoke dataset on the laptop.

**What printed**

The run did not fail. All three MARKDUPLICATES tasks ran and exited 0, and so did the stages after them. But the task did the wrong thing without saying so. I aimed at an error and got silent wrong output: the module says `echo "markdup finished $(date)"`, the task's `.command.sh` says `echo "markdup finished date)"`, and the task printed `markdup finished date)` instead of a date.

**Evidence from the task folder (`work/58/18afd8...`, smoke_01)**

`.command.sh`:

```
#!/bin/bash -euo pipefail
gatk MarkDuplicates -I smoke_01.bam -O smoke_01.md.bam -M smoke_01.md.metrics.txt
samtools index smoke_01.md.bam
echo "markdup finished date)"
```

`.command.err` (last lines): only Picard's normal INFO logging, ending with `MarkDuplicates done. Elapsed time: 0.03 minutes.` No error.

`bash .command.run` in that folder ran the task again in its container: `Tool returned: 0`, and the last line of output was `markdup finished date)`.

**Why / fix**

In a script block Nextflow fills in every `$` itself before bash sees the script. With the backslash gone, the `$(` did not reach `.command.sh`; only `date)` did. Bash therefore never ran `date`, and nothing complained, because what is left is a valid string. That is the dangerous kind of failure: exit 0 and wrong output. Other dollar signs fail more loudly: a bash variable such as `$n` stops Nextflow before any task runs, with `n is not defined`, and `$2` inside an awk program runs without an error and prints the wrong thing (both are noted on the assignment page; I only tested `$(date)`). Fix: put the backslash back, `\$(date)`, which I did with `git checkout modules/markduplicates.nf`. The rule is `${name}` for a Nextflow value and `\$` for every `$` that bash should see, and `.command.sh` shows exactly what bash received.

---

## 4. `time = '2m'` for HAPLOTYPECALLER on the first Explorer run

**Command**

Added to the `explorer` profile in `nextflow.config`, after the `BWA_MEM|HAPLOTYPECALLER` block so that the later selector wins:

```groovy
withName: 'HAPLOTYPECALLER' {
    time = '2m'
}
```

then `sbatch slurm/nextflow.sbatch` on Explorer.

**What printed**

Nextflow stopped with:

```
Process `HAPLOTYPECALLER (NA07357)` terminated with an error exit status (140)
```

`sacct -X` for the HaplotypeCaller jobs:

| Job | State | Elapsed | Timelimit | ExitCode |
|---|---|---|---|---|
| nf-HAPLOTYPECALLER_(NA07357) | FAILED | 00:01:20 | 00:02:00 | 12:0 |
| nf-HAPLOTYPECALLER_(NA12892) | FAILED | 00:01:18 | 00:02:00 | 12:0 |
| nf-HAPLOTYPECALLER_(NA12891) | FAILED | 00:01:02 | 00:02:00 | 12:0 |
| the other three | CANCELLED+ | 00:00:18 to 00:00:37 | 00:02:00 | 0:0 |

I expected `TIMEOUT` at two minutes. I got `FAILED` at about one minute twenty seconds.

**Why / fix**

Nextflow asks Slurm to send the job a warning signal (USR2) 30 seconds before its time limit, and stops the task when the warning arrives. So the task ended on that signal, not at the limit itself: exit status 140 is 128 plus signal 12, matching `12:0` in `sacct`, and Slurm recorded `FAILED` and not `TIMEOUT`. The other three tasks were cancelled by Nextflow when the run stopped. Fix: put `time = '1h'` back (`git checkout nextflow.config`) and submit again. `-resume` does not rerun a task just because its time limit changed, since `cpus`, `memory` and `time` are not part of what Nextflow compares. So the tasks that had finished (VALIDATE, FASTQC, FASTP, BWA_MEM, MARKDUPLICATES) were reused and the run carried on from HAPLOTYPECALLER.

---

## Also hit (not one of the four): Apptainer image pulls on Explorer

The first two Explorer attempts stopped before any analysis. One head job failed with `no descriptor found for reference` while Nextflow pulled several images at once, and a later run's FASTP task exited 127 (`fastp: command not found`) from a damaged cached image. I removed the bad `.img` files and the Apptainer cache, then pulled the six images one at a time in a small Slurm job into `/scratch/$USER/nxf-apptainer`. Nextflow found them cached and the run started normally.
