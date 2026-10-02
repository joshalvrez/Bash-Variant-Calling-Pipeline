# RESOURCES.md — what I measured and what I changed

## The short version

| | asked for first | what the measurements said | set to | why |
|---|---|---|---|---|
| per-sample `--cpus-per-task` | 8 | 2.94 cores busy at 8; 8 cores is only 1:13 faster than 4 | **4** | 4 is where more cores stop paying for themselves |
| per-sample `--mem` | 16G | `MaxRSS` 5.9–13.3 GiB over eight samples; `memory.peak` up to 13.6 GiB | **16G** (kept) | the first request is already just above the highest peak |
| per-sample `--time` | 01:00:00 | longest of eight tasks: 11:06 | **00:30:00** | more than twice the longest task |
| cohort `--cpus-per-task` | 2 | 1.04 cores busy | **2** (kept) | the cohort stages are single-threaded; nothing to gain |
| cohort `--mem` | 8G | `MaxRSS` 1.16 GB, `memory.peak` 1.19 GiB | **4G** | still more than three times the peak |
| cohort `--time` | 01:00:00 | 8:57 | **00:30:00** | more than three times what it took |

## 1 - first run: all eight samples

`bash slurm/submit.sh` with `--cpus-per-task=8 --mem=16G --time=01:00:00` per sample and
`--cpus-per-task=2 --mem=8G --time=01:00:00` for the cohort job. Array `10754529`, cohort `10754530`.

```
$ sacct -j 10754529,10754530 --format=JobID,State,ExitCode,Elapsed,MaxRSS,AllocCPUS
JobID             State ExitCode    Elapsed     MaxRSS  AllocCPUS
------------ ---------- -------- ---------- ---------- ----------
10754530      COMPLETED      0:0   00:08:57                     2
10754530.ba+  COMPLETED      0:0   00:08:57   1219212K          2
10754529_1    COMPLETED      0:0   00:08:40                     8
10754529_1.+  COMPLETED      0:0   00:08:40   7144532K          8
10754529_2    COMPLETED      0:0   00:07:42                     8
10754529_2.+  COMPLETED      0:0   00:07:42   7139820K          8
10754529_3    COMPLETED      0:0   00:05:09                     8
10754529_3.+  COMPLETED      0:0   00:05:09   6141220K          8
10754529_4    COMPLETED      0:0   00:07:04                     8
10754529_4.+  COMPLETED      0:0   00:07:04  13820512K          8
10754529_5    COMPLETED      0:0   00:05:17                     8
10754529_5.+  COMPLETED      0:0   00:05:17   6241124K          8
10754529_6    COMPLETED      0:0   00:07:10                     8
10754529_6.+  COMPLETED      0:0   00:07:10  13928556K          8
10754529_7    COMPLETED      0:0   00:11:06                     8
10754529_7.+  COMPLETED      0:0   00:11:06   8146924K          8
10754529_8    COMPLETED      0:0   00:09:33                     8
10754529_8.+  COMPLETED      0:0   00:09:33   7628608K          8
```

(The `.extern` step lines are left out; they are all under 1 MB.)

The eight tasks took between 5:09 and 11:06. `MaxRSS` was between 6141220K (5.9 GiB) and
13928556K (13.3 GiB), so the 16G request was not far above the largest sample.

The cohort job:

```
$ seff 10754530
Job ID: 10754530
Cluster: explorer
User/Group: alvarez.josh/users
State: COMPLETED (exit code 0)
Nodes: 1
Cores per node: 2
CPU Utilized: 00:09:17
CPU Efficiency: 51.86% of 00:17:54 core-walltime
Job Wall-clock time: 00:08:57
Memory Utilized: 1.16 GB
Memory Efficiency: 14.53% of 8.00 GB

$ grep memory.peak logs/cohort_10754530.out
memory.peak (bytes): 1280794624
```

CPU Utilized ÷ wall clock = 9:17 ÷ 8:57 = **1.04 cores busy** out of 2. Memory peaked at
1.19 GiB out of 8 GB.

## 2 · core-count comparison: one sample, three values of `--cpus-per-task`

The same sample (`NA12878`, row 1) run from an empty run directory each time, changing only `--cpus-per-task`. Jobs `10764466`, `10764467`, `10764468`.

```
$ sacct -j 10764466,10764467,10764468 --format=JobID%16,State,Elapsed,TotalCPU,MaxRSS,AllocCPUS
           JobID      State    Elapsed   TotalCPU     MaxRSS  AllocCPUS
---------------- ---------- ---------- ---------- ---------- ----------
      10764466_1  COMPLETED   00:15:32  19:51.567                     2
10764466_1.batch  COMPLETED   00:15:32  19:51.565   8201436K          2
      10764467_1  COMPLETED   00:08:50  19:46.194                     4
10764467_1.batch  COMPLETED   00:08:50  19:46.193   6812692K          4
      10764468_1  COMPLETED   00:07:37  22:25.389                     8
10764468_1.batch  COMPLETED   00:07:37  22:25.388   7156256K          8

$ grep memory.peak logs/persample_1076446[678]_1.out
logs/persample_10764466_1.out:memory.peak (bytes): 8736714752
logs/persample_10764467_1.out:memory.peak (bytes): 14622179328
logs/persample_10764468_1.out:memory.peak (bytes): 14286376960
```

| `--cpus-per-task` | wall clock | CPU time | cores busy (CPU ÷ wall) | wall saved vs previous | core-minutes (cores × wall) | `MaxRSS` | `memory.peak` |
|---|---|---|---|---|---|---|---|
| 2 | 15:32 | 19:52 | 1.28 | — | 31.1 | 7.8 GiB | 8.1 GiB |
| **4** | **8:50** | 19:46 | 2.24 | **−6:42** | 35.3 | 6.5 GiB | 13.6 GiB |
| 8 | 7:37 | 22:25 | 2.94 | −1:13 | 60.9 | 6.8 GiB | 13.3 GiB |

Going from 2 - 4 cores cut the wall clock by 6:42 for almost the same core-minutes. From 4 - 8 --> cut it by only 1:13 and cost 60.9 core-minutes instead of 35.3. At 8 cores, <3 were busy because only some stages (`bwa mem`, `samtools sort`) use the threads they are given.

`MaxRSS` is sampled every 30 seconds and can miss a short peak. `memory.peak` is the exact high-water mark of the job's cgroup, which also counts file cache. I used the larger number when deciding `--mem`.

## 3 · What I changed

**Per-sample job (`slurm/01_persample.sbatch`)**

- `--cpus-per-task`: **8 → 4.** The knee is at 4. Eight cores saved 1:13 per sample and kept under 3 cores busy, so half of the allocation was idle.
- `--mem`: **16G, unchanged.** The highest values measured were 13.3 GiB (`MaxRSS`, samples 4 and 6 of the full run) and 13.6 GiB (`memory.peak`, the 4-core probe). 16G is just above that, so the measurement said the first request was right and lowering it would go under the peak.
- `--time`: **01:00:00 → 00:30:00.** The longest task of the full run was 11:06 at 8 cores, and the probe was 16 % slower at 4 cores than at 8 (8:50 against 7:37), so the longest task should take about 13 minutes. 30 minutes is more than twice that.

**Cohort job (`slurm/02_cohort.sbatch`)**

- `--cpus-per-task`: **2, unchanged.** 1.04 cores were busy; the cohort stages are single-threaded, and more cores would not make them faster.
- `--mem`: **8G → 4G.** The job used 1.16 GB (`seff`) and peaked at 1.19 GiB (`memory.peak`), 14.53 % of the request. 4G is still more than three times the peak.
- `--time`: **01:00:00 → 00:30:00.** The job took 8:57. I left a wide margin on purpose, because a `TIMEOUT` here would throw away the work of all eight array tasks.

NOTE: `cluster-run/` was produced by the first run at 8 cores / sample. `bwa mem` batches its input by thread count --> rerun at 4 cores can align a few read pairs differently.
