# TROUBLESHOOTING.md — four failures I caused on purpose

## 1 · `--time=00:02:00`

```bash
sbatch -p courses -A binf6610.202710 --array=1 --time=00:02:00 \
       --export=RUN_ROOT=/scratch/$USER/brk1 01_persample.sbatch
```

```
           JobID      State ExitCode    Elapsed
      10764469_1    TIMEOUT      0:0   00:02:46
```

The `State` is `TIMEOUT`, and the exit code is `0:0`: my script did not return an error. Slurm stopped it from outside. log stopped in the middle of stage 5. only line that says why was written by Slurm:

```
[15:02:02] NA12878: sorted, duplicates marked, indexed
[15:02:02] ===== NA12878 : stage 5 : quantify =====
slurmstepd: error: *** JOB 10764469 ON c0617 CANCELLED AT 2026-10-02T15:02:53 DUE TO TIME LIMIT ***
```

The elapsed time is 2:46 v. 2:00 limit --> Slurm did not stop a job at time limit. What was left on disk was the finished outputs of stages 2 and 4 (`trim/NA12878_trimmed_R1.fastq.gz`, `trim/NA12878_trimmed_R2.fastq.gz`, `align/NA12878.dedup.bam` and its `.bai`), and ahalf-written file from stage 5:

```
/scratch/alvarez.josh/brk1/variants:
-rw-r--r-- 1 alvarez.josh users 3494885 Oct  2 15:02 NA12878.tmp.g.vcf.gz
```

there is no `NA12878.g.vcf.gz` --> rerun would not mistake it for finished GVCF

## 2 · One task exits 1, with the cohort job on `afterok`

`01_persample.sbatch` has small hook that makes the task whose number equals `FAIL_TASK` exit 1 before it runs anything.

```bash
A=$(sbatch --parsable -p courses -A binf6610.202710 --array=1-3 \
           --export=FAIL_TASK=2,RUN_ROOT=/scratch/$USER/brk2 01_persample.sbatch)
sbatch -p courses -A binf6610.202710 --dependency=afterok:$A --kill-on-invalid-dep=yes \
       --export=RUN_ROOT=/scratch/$USER/brk2 02_cohort.sbatch
```

```
           JobID      State ExitCode    Elapsed
      10764470_1  COMPLETED      0:0   00:07:36
      10764470_2     FAILED      1:0   00:00:14
      10764470_3  COMPLETED      0:0   00:05:49
        10764473  CANCELLED      0:0   00:00:00
```

```
task 2 (NA12891): failing on purpose, FAIL_TASK=2
```

2/3 of samples succeeded and cohort job never started; `State` is `CANCELLED` with elapsed time of 00:00:00. While waiting; `squeue` showed as `PD` with the reason `(Dependency)`

```
10764473   courses w2-cohor alvarez. PD       0:00      1 (Dependency)
```

Didn't capture `Reason=Dependency` after it was cancelled. `sacct`'s `Reason` column printed `None`. Slurm job record: `slurm_load_jobs error: Invalid job id specified`. 

## 3 · `--array=1-9` against the eight-row samplesheet

```bash
sbatch -p courses -A binf6610.202710 --array=1-9 \
       --export=RUN_ROOT=/scratch/$USER/brk3 01_persample.sbatch
```

```
           JobID      State ExitCode    Elapsed
      10764474_1  COMPLETED      0:0   00:07:33
      10764474_2  COMPLETED      0:0   00:08:53
      10764474_3  COMPLETED      0:0   00:05:12
      10764474_4  COMPLETED      0:0   00:07:10
      10764474_5  COMPLETED      0:0   00:05:25
      10764474_6  COMPLETED      0:0   00:07:33
      10764474_7  COMPLETED      0:0   00:10:48
      10764474_8  COMPLETED      0:0   00:09:01
      10764474_9     FAILED     64:0   00:00:13
```

```
task 9: no row 9 in /courses/BINF6610.202710/data/samplesheet-variant8.csv
```

Tasks 1 to 8 ran samples. Task 9 refused by the guard in the job script, with exit code 64.
If there was no guard, `SAMPLE` would have been empty for task 9; `run_sample.sh` would still have refused it, because it required a non-empty sample that is located within  the sheet.

## 4 · `scancel` in the middle of a write, then resubmit

```bash
J=$(sbatch --parsable -p courses -A binf6610.202710 --array=1 \
           --export=RUN_ROOT=/scratch/$USER/brk4 01_persample.sbatch)
# waited until the log showed "stage 3 : align", then:
scancel $J
```

```
           JobID      State ExitCode    Elapsed
      10765935_1 CANCELLED+      0:0   00:01:47
```

```
[15:30:01] NA12878: trimmed to 1222355 reads
[15:30:01] ===== NA12878 : stage 3 : align =====
slurmstepd: error: *** JOB 10765935 ON c3014 CANCELLED AT 2026-10-02T15:31:00 ***
```

The cancel happened while `bwa mem` was writing the alignment. This is what it left behind:

```
/scratch/alvarez.josh/brk4/align:
-rw-r--r-- 1 alvarez.josh users 476807168 Oct  2 15:31 NA12878.sam.tmp

/scratch/alvarez.josh/brk4/trim:
-rw-r--r-- 1 alvarez.josh users 87230844 Oct  2 15:29 NA12878_trimmed_R1.fastq.gz
-rw-r--r-- 1 alvarez.josh users 91236895 Oct  2 15:29 NA12878_trimmed_R2.fastq.gz
```

A 477 MB partial SAM named `NA12878.sam.tmp`; NOT `NA12878.sam`. Resubmitted command (job `10765978`):

```
[15:31:25] NA12878: inputs already verified
[15:31:25] NA12878: qc already done
[15:31:25] NA12878: trim already done
[15:32:58] NA12878: aligned
```

Rerun trusted the three stages that had finished them. Did not trust the partial alignment: stage 3 only skips when `NA12878.sam` exists, so it ran `bwa mem` again from the start, taking up 93 seconds, and overwrote fragment. By 15:33 stage 4 produced a complete `NA12878.dedup.bam` (132 MB) and its index. Job was still running stage 5 this was captured

If stage 3 had written straight to `NA12878.sam` --> rerun would have found a non-empty file under its real name which would have skipped alignment; stage 4 would have sorted a truncated SAM. Writing to `.tmp` name and renaming after the tool exits 0 is what prevents that.


## AI acknowledgement

I used Claude Opus 5.5 as an assistant for Assignment 2 for the following:

- **Code structure.** Claude helped me split my week-1 `run_pipeline.sh` into `lib/common.sh` and one file per stage in `stages/`, following the layout of the provided in the demo as well as the grading section of the assignment page. Claude also wrote and helped me breakdown and understand the `run_sample.sh` and the four files in `slurm/` by adapting the demo provided on Canvas to my variant-calling pipeline. Claude also assisted me with splitting my original `run_pipeline.sh` script into `lib/` and `stages/`. All of which was read and edited whenever I needed to. The tool commands and settings in each stage are from my week-1 pipeline.
- **Running on Explorer.** Claude broke down and helped me upderstand the commands I had to use for the Explorer portion of the project. It also helped me create the array and run the core-count probes as well as the four deliberate failures. I ran every job myself on Explorer and all job ids, `sacct`/`seff` output and log lines in this repository are from my own runs.
- **Write-ups.** Claude drafted `RESOURCES.md` and `TROUBLESHOOTING.md` from the output I collected. I reviewed and edited both.