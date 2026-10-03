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

Tasks 1 to 8 ran samples. Task 9 refused by the guard in the job script, with exit code 64. If there was no guard, `SAMPLE` would have been empty for task 9; `run_sample.sh` would still have refused it, because it required a non-empty sample that is located within  the sheet.

## 4 · `scancel` in the middle of a write, then resubmit

```bash
J=$(sbatch --parsable -p courses -A binf6610.202710 --array=1 \
           --export=RUN_ROOT=/scratch/$USER/brk4 01_persample.sbatch)
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

I used Claude Opus 5.5 as an assistant for Assignment 3 for the following:

- Claude wrote and broke down key details around the `containers/Dockerfile` and `slurm/pull.sbatch` by adapting the demo's Dockerfile and the script on the assignment page to my pipeline's tools, changed the last line of both job scripts to run through `apptainer exec`, updated `slurm/conf/slurm.env`, and drafted `IMAGE.md`. I read each file and can edit them as needed.
- Claude gave me the commands to build, check and push the image, fetch it onto Explorer, submit the run, compare the versions and record checksums, and cause the four failures. On my end, I ran every command myself on my laptop and on Explorer, and all digests, job ids and output in this repository are from my own runs.
- Claude drafted the week-3 section of `TROUBLESHOOTING.md` and the sentence in `cluster-run-container/records-sha256.txt` from the output I collected. I reviewed them.
---

# Week 3 — four failures with the container, caused on purpose

Failure 1 was on my laptop; failures 2 to 4 were on Explorer. Each has the command, what it printed, and the fix.

## W3-1 · An unpinned recipe, built twice
In a scratch directory, a recipe with no tag on the base image and no version on the package:

```dockerfile
FROM ubuntu
RUN apt-get update && apt-get install -y curl
```

```bash
docker build -t breakage:one .
docker run --rm breakage:one dpkg -l > one.txt
docker build --pull --no-cache -t breakage:two .
docker run --rm breakage:two dpkg -l > two.txt
wc -l one.txt two.txt
diff one.txt two.txt
```

What it printed:

```
first build:   [1/2] FROM docker.io/library/ubuntu:latest@sha256:66460d557b25769b102175144d538d88219c077c678a49af4afca6fbfc1b5252
second build:  [1/2] FROM docker.io/library/ubuntu:latest@sha256:3595d7fc4286a33fad0fd853a4063e654287a9c3787437d7937c94ca3f7a804e

     118 one.txt
     122 two.txt
diff exit code: 1
1,118c1,122
```

```
< ii  coreutils        9.4-3ubuntu6.1
< ii  curl             8.5.0-2ubuntu10.15
< ii  ca-certificates  20260601~24.04.1
> rust-coreutils 0.10.0-1ubuntu2~26.04.1
> openssl 3.5.5-1ubuntu3.7
> util-linux 2.41.3-3ubuntu2.2
```

I aimed at a difference caused by a day passing between two builds, and I did not have a day: the builds were less than an hour apart. I still got a large difference, for a
different reason. The first build did not use `--pull`, so it took the copy of `ubuntu:latest` that was already on my laptop, which was an older one; the version strings (`~24.04.1` against `~26.04.1`) say the two bases are not even the same Ubuntu release. The second build, with `--pull --no-cache`, fetched whatever `latest` meant that minute and re-ran `apt-get`. So what `FROM ubuntu` means depends on the machine and the day.

**The fix** is what `containers/Dockerfile` does: a base image with a tag that is not
`latest` (`mambaorg/micromamba:2.0.5-ubuntu24.04`), and `=version` on every tool.

## W3-2 · `--bind` removed from one job script

```bash
sed '/--bind/d' 01_persample.sbatch > brk_nobind.sbatch
sbatch -p courses -A binf6610.202710 --array=1 \
       --export=RUN_ROOT=/scratch/$USER/w3-brk2 brk_nobind.sbatch
```

```
           JobID      State ExitCode    Elapsed  AllocCPUS
      10773322_1     FAILED     65:0   00:00:02          4
```

```
task 1 on c0617: NA12878, 4 cores, run root /scratch/alvarez.josh/w3-brk2
error: no samplesheet: /courses/BINF6610.202710/data/samplesheet-variant8.csv
```

It stopped after two seconds, before stage 0, with exit code 65. The path the container
could not see was `/courses/BINF6610.202710`: the first line of the log shows that the job script, outside the container, had just read the samplesheet and found `NA12878` in it, and the second line is `run_sample.sh`, inside the container, saying the same file is not there. Without `--bind` the container sees my home directory, `/tmp` and the directory I submitted from, and nothing under `/courses` or `/scratch`. 

**The fix** is the line that was removed: `--bind /courses/BINF6610.202710,/scratch/${USER}`.

## W3-3 · `--env THREADS=…` removed from one job script

```bash
sed '/--env THREADS=/d' 01_persample.sbatch > brk_nothreads.sbatch
sbatch -p courses -A binf6610.202710 --array=1 --cpus-per-task=8 \
       --export=RUN_ROOT=/scratch/$USER/w3-brk3 brk_nothreads.sbatch
```

I asked for 8 cores on the command line, because my job script asks for 4 and the pipeline's
own default is also 4, so at 4 the missing variable would not show.

```
           JobID      State ExitCode    Elapsed  AllocCPUS
      10773323_1  COMPLETED      0:0   00:08:26          8
```

```
task 1 on c0617: NA12878, 8 cores, run root /scratch/alvarez.josh/w3-brk3
```

```
$ grep 'CMD:' /scratch/alvarez.josh/w3-brk3/logs/NA12878.bwa.log
[main] CMD: bwa mem -t 4 -R @RG\tID:NA12878\tSM:NA12878 /courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa /scratch/alvarez.josh/w3-brk3/trim/NA12878_trimmed_R1.fastq.gz /scratch/alvarez.josh/w3-brk3/trim/NA12878_trimmed_R2.fastq.gz
```

Nothing failed: the job is `COMPLETED` with `0:0`. It held 8 cores and `bwa mem` ran with `-t 4`. Under `--cleanenv` the `THREADS` the job script exported did not cross into the container, so `lib/common.sh` fell back to its default of 4. The only place this shows is the tool's own log.

**The fix** is the line that was removed: `--env THREADS="${THREADS}"`.

## W3-4 · An arm64 image on Explorer

```bash
cd /scratch/$USER
export APPTAINER_CACHEDIR=/scratch/$USER/apptainer-cache
apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04
apptainer exec arm.sif cat /etc/os-release
```

```
INFO:    Creating SIF file...
pull exit code: 0
FATAL:   While checking container encryption: could not open image /scratch/alvarez.josh/arm.sif: the image's architecture (arm64) could not run on the host's (amd64)
run exit code: 255
```

The pull succeeded with exit code 0 and no warning. Only running something out of the image failed, with exit code 255, and the message names the two architectures.

**The fix** is to build for Explorer's CPU and check before pushing:
`docker build --platform linux/amd64 ...`, then
`docker image inspect --format '{{.Architecture}}' <image>` must print `amd64`.
