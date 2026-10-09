# Assignment 4 — Your variant-calling pipeline, in Nextflow

Due one week from the session. Submit a link to the same Git repository as weeks 1–3.

Your pipeline has run three ways: on your laptop, as a Slurm array on Explorer, and inside an image.
Each time the ten stages stayed the same and the code around them changed — the loop over the
samplesheet, the skip-if-done tests, the job array and `afterok`, the `apptainer exec` line. This week
you write the ten stages as Nextflow processes, and Nextflow does the rest. One `main.nf` runs them on
your laptop, on the smoke dataset, and on Explorer, on the eight samples.

## What you are adding

```
your-repo/
├── main.nf                  # reads the samplesheet and connects the ten processes
├── modules/                 # one process per stage, one file each
│   └── publish.nf           # stage 9, from this archive, unchanged
├── bin/                     # the scripts your processes run
│   └── run_manifest.sh      # from this archive, unchanged
├── nextflow.config          # parameters, the images, profiles docker and explorer
├── slurm/nextflow.sbatch    # the head job on Explorer
├── smoke-run-nf/            # your laptop run, on the smoke dataset
├── cluster-run-nf/          # your Explorer run, on the eight samples
└── TROUBLESHOOTING.md       # four failures you caused on purpose
```

Your weeks 1–3 pipeline stays where it is: this is a second implementation of the same pipeline,
beside the first, and step 9 compares their results.

## Before you start

- **Nextflow on your laptop, and the six images downloaded**: the page *Week 4 — Setup: Nextflow on
  your laptop*.
- **Week 1's smoke dataset.** The commands below assume the `smoke/` folder is at `~/smoke`; if yours
  is somewhere else, use that path instead.
- **This archive, unzipped into a folder of its own** — the commands below assume `~/a4`. It holds
  the tests and the two course files of step 1.
- **On Explorer, nothing to install.** The course environment has Nextflow 26.04.6.
- **The demo.** The page *Week 4 — The demo, end to end* has the session's RNA-seq pipeline
  written the way this assignment asks for yours: the same files, the same ten stages, other tools.

## The steps

### 1 · Put the two course files in place

```bash
cd ~/your-repo
mkdir -p modules bin
cp ~/a4/modules/publish.nf modules/
cp ~/a4/bin/run_manifest.sh bin/
chmod +x bin/run_manifest.sh
```

`publish.nf` is stage 9: it writes `samples.tsv` and `manifest.json`. `run_manifest.sh` is the script
it runs. Use both unchanged.

### 2 · Read the samplesheet in `main.nf`

The session's code, which reads each row by column name and makes one item per sample,
`[meta, reads]`:

```groovy
sheet = file(params.samplesheet)
ch_samples = channel.fromPath(sheet)
    .splitCsv(header: true)
    .map { row ->
        def meta = [id: row.sample_id, single_end: row.library_type == 'single']
        def r1 = sheet.parent.resolve(row.r1_fastq)
        def reads = meta.single_end ? [r1] : [r1, sheet.parent.resolve(row.r2_fastq)]
        [meta, reads]
    }
```

`meta` is a map, `[id: 'smoke_01', single_end: false]`, and `reads` is one file for a single-end
sample and two for a paired one. It reads both samplesheets unchanged: the smoke one names its
FASTQs relative to its own folder, and the course's eight-sample one on Explorer gives full paths.

Every per-sample process takes the item as `tuple val(meta), path(reads)` and passes `meta` on in its
output, `tuple val(meta), path(...)`. Inside a process, `${meta.id}` is the sample's name — for `tag`
and for file names — and `meta.single_end` chooses fastp's paired or single-end command. The one
exception: an output that goes only, through `collect()`, to a stage that runs once is a plain `path`
— FASTQC's zip, FASTP's report, HaplotypeCaller's GVCF and its index. A `collect()` of
`[meta, file]` items hands a `path` input the maps too, and the run stops with
`Not a valid path value type: java.util.LinkedHashMap`.

### 3 · Write one process per stage

Each stage of your weeks 1–3 pipeline becomes one process, in a file of its own under `modules/`, and
the commands inside it are your week-1 commands. The process names are yours; these are the ones the
demo and the reference use:

| stage | process | image | runs once per |
|---|---|---|---|
| 0 validate | `VALIDATE` | `tools` | run |
| 1 qc_raw | `FASTQC` | `fastqc` | sample |
| 2 trim | `FASTP` | `fastp` | sample |
| 3 align | `BWA_MEM` | `bwa` | sample |
| 4 postprocess | `MARKDUPLICATES` | `gatk` | sample |
| 5 quantify | `HAPLOTYPECALLER` | `gatk` | sample |
| 6 merge | `JOINT_GENOTYPE` | `gatk` | run |
| 7 analyze | `FILTER` | `gatk` | run |
| 8 qc_report | `MULTIQC` | `multiqc` | run |
| 9 publish | `PUBLISH`, from step 1 | `tools` | run |

Each process names its image with `container params.containers.<image>`, the key in the table's
image column. What the session showed, and where each rule comes up:

- **Every `$` that bash should see is written `\$` inside a script block**, and a backslash is written
  `\\`. A command full of both is easier to move into a script in `bin/`, which is on every task's
  `PATH`.
- **The reference, its `.fai`, its `.dict` and its BWA index are value channels**: `file()` and
  `files()`, never `channel.fromPath`. A reference given as a queue channel is used by one sample.
  The reference solution's three lines, at the top of the workflow:

  ```groovy
  ref       = file(params.ref)                                // the FASTA
  ref_index = files("${params.ref}.*")                        // its .fai and the BWA index
  ref_dict  = file("${ref.parent}/${ref.baseName}.dict")      // GATK's sequence dictionary
  ```

  The dictionary is `smoke.dict`, not `smoke.fa.dict`, so `smoke.fa.*` does not find it.
- **A process with two outputs names them with `emit:`**: FASTP's trimmed reads go to `BWA_MEM` and
  its report to `MULTIQC`, so its outputs are `tuple val(meta), path('*.trim.fastq.gz'), emit: reads`
  and `path "${meta.id}.fastp.json", emit: json`, read as `FASTP.out.reads` and `FASTP.out.json`.
- **Threads come from `task.cpus`**: `bwa mem -t ${task.cpus}`, and
  `--native-pair-hmm-threads ${task.cpus}` for HaplotypeCaller.
- **Stage 6 takes every sample's GVCF, and its index, at once**: `HAPLOTYPECALLER.out.gvcf.collect()`
  and `HAPLOTYPECALLER.out.tbi.collect()`, two inputs. GATK reads a `.g.vcf.gz` only with its `.tbi`
  beside it.
- **Stage 7 also writes `variants.tsv`**: a header line `chrom pos ref alt qual filter`, tab-separated,
  then one line per record of `cohort.filtered.vcf.gz`:

  ```bash
  printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > variants.tsv
  bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' cohort.filtered.vcf.gz >> variants.tsv
  ```

  That is how it reads in bash; inside a script block every `\` in it is `\\`.
- **No process copies its own results out of `work/`.** Stages 7, 8 and 9 reach `results/` through
  `publish:` and an `output` block at the end of `main.nf` — step 6.

### 4 · Stage 0 opens every FASTQ by its file name, and every sample waits for it

A task runs in a folder of its own, so the paths in the samplesheet do not lead anywhere from inside
`VALIDATE`. Give it every FASTQ as an input, and Nextflow links each one into its folder:

```groovy
VALIDATE(sheet, ch_samples.map { _meta, reads -> reads }.collect(),
         ref, ref_index, ref_dict)
```

Your week-1 stage-0 checks move into `bin/validate_samplesheet.sh` (the name is yours), changed in one
way: each FASTQ is opened by its file name, `$(basename "$r1")`, not by the path the samplesheet
gives. `VALIDATE`'s output is the samplesheet itself, `path samplesheet, emit: sheet`.

Then make every sample wait until stage 0 has passed, and feed the per-sample stages from
`ch_checked` instead of `ch_samples`:

```groovy
ch_checked = ch_samples
    .combine(VALIDATE.out.sheet)
    .map { meta, reads, _validated -> [meta, reads] }
```

`combine` pairs every sample with `VALIDATE`'s one output, so no sample reaches `FASTQC` or `FASTP`
until `VALIDATE` has succeeded; `map` then drops the samplesheet again. The demo's `main.nf` has the
same three lines.

### 5 · `nextflow.config`

Start from this. The images are the course environment's versions, one per kind of step; the Explorer
settings are week 2's measurements.

```groovy
manifest {
    name    = 'variant-call'
    version = '1.0.0'
}

params {
    samplesheet = null
    ref         = null
    region      = null
    outdir      = 'results'
    platform    = 'laptop'

    containers = [
        tools  : 'community.wave.seqera.io/library/coreutils_gawk_gzip:7c58ccc2f9ca6bcc',
        fastqc : 'quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0',
        fastp  : 'community.wave.seqera.io/library/fastp:1.3.7--075357a9d5c82494',
        bwa    : 'community.wave.seqera.io/library/bwa_samtools:22527ddb3cc80fb3',
        gatk   : 'community.wave.seqera.io/library/gatk4_samtools_bcftools:1adede7d418fb46b',
        multiqc: 'quay.io/biocontainers/multiqc:1.35--pyhdfd78af_2'
    ]
}

outputDir            = params.outdir
workflow.output.mode = 'copy'

process {
    cpus   = 1
    memory = '2 GB'
    shell  = ['/bin/bash', '-euo', 'pipefail']
}

trace {
    enabled   = true
    overwrite = true
    file      = "${params.outdir}/pipeline_info/trace.txt"
    fields    = 'task_id,name,status,exit,container,native_id,realtime,%cpu,peak_rss'
}
report {
    enabled   = true
    overwrite = true
    file      = "${params.outdir}/pipeline_info/report.html"
}

profiles {
    docker {
        params.platform   = 'docker-local'
        docker.enabled    = true
        docker.runOptions = '--platform linux/amd64'
    }
    explorer {
        params.platform = 'singularity-hpc'
        process {
            executor       = 'slurm'
            queue          = 'courses'
            clusterOptions = '--account=binf6610.202710'
            time           = '30m'
            withName: 'BWA_MEM|HAPLOTYPECALLER' {
                cpus   = 8
                memory = '16 GB'
                time   = '1h'
            }
            withName: 'MARKDUPLICATES|JOINT_GENOTYPE|FILTER' {
                cpus   = 2
                memory = '8 GB'
                time   = '1h'
            }
        }
        apptainer {
            enabled    = true
            autoMounts = true
        }
    }
}
```

If your process names differ from the table in step 3, change the two `withName:` lines to match.
`outputDir` is where the `output` block of step 6 puts the results, so `--outdir` still chooses the
folder, and `workflow.output.mode = 'copy'` makes them copies rather than links into `work/`.
`shell` gives every task week 1's `set -euo pipefail`. Nextflow's own is `bash -ue`, and without
`pipefail` a pipe succeeds whenever its last command does: measured with Nextflow 26.04.6,
`lines=$(gzip -dc no_such_file.fastq.gz | wc -l)` exited 0 and set `lines` to 0.

### 6 · The manifest, and publishing the results

`publish.nf` records the run from what Nextflow knows about it: `manifest.name` and
`manifest.version` from the config, `params.platform` from the profile, the image table, every
parameter the run was given, and every file it describes, with its checksum. Call it at the end of
your workflow, with your stage 7 and stage 8 outputs:

```groovy
PUBLISH(VALIDATE.out.sheet, FILTER.out.vcf.mix(FILTER.out.table, MULTIQC.out).collect())
```

`mix` puts the outputs of three channels into one, and `collect` hands them to `PUBLISH` together.

Then publish stages 7, 8 and 9. `PUBLISH`'s two outputs are named `manifest` and `samples`. Once a
workflow has `publish:`, the code above it goes under `main:`:

```groovy
workflow {
    main:
    // ... everything from steps 2 to 4, the processes, and PUBLISH

    publish:
    vcf      = FILTER.out.vcf
    variants = FILTER.out.table
    multiqc  = MULTIQC.out
    manifest = PUBLISH.out.manifest
    samples  = PUBLISH.out.samples
}

output {
    vcf {
        path '.'
    }
    variants {
        path '.'
    }
    multiqc {
        path '.'
    }
    manifest {
        path '.'
    }
    samples {
        path '.'
    }
}
```

`path '.'` puts each at the top of `results/`. Every name under `publish:` needs its block here, or
the run stops before it starts. The page *Week 4 — Your manifest from Nextflow* shows a manifest and
what each field is for.

### 7 · Run it on your laptop, on the smoke dataset

```bash
cd ~/your-repo
nextflow run main.nf -profile docker \
    --samplesheet ~/smoke/samplesheet.csv --ref ~/smoke/smoke.fa --region smoke_1mb
```

The reference solution took 4 to 5 minutes on a MacBook Air, with the images already downloaded. Then
copy what the run published, and commit it:

```bash
mkdir -p smoke-run-nf
cp -R results/. smoke-run-nf/
git add -f smoke-run-nf
```

`-f`, because a `.gitignore` that ignores VCFs makes `git add` skip them without a word.

Add these to `.gitignore`: Nextflow's working files, and `results/`, whose copies you commit instead.

```
work/
.nextflow/
.nextflow.log*
results/
nf-head-*.out
```

### 8 · Run it on Explorer, on the eight samples

Nextflow runs as a Slurm job, the head job, and submits every task as a job of its own.
`slurm/nextflow.sbatch`:

```bash
#!/bin/bash
#SBATCH --job-name=nf-head
#SBATCH --account=binf6610.202710
#SBATCH --partition=courses
#SBATCH --cpus-per-task=2
#SBATCH --mem=16G
#SBATCH --time=04:00:00
#SBATCH --output=nf-head-%j.out
#SBATCH --export=NONE
set -euo pipefail

module load miniconda3/25.9.1
source activate /courses/BINF6610.202710/shared/env/binf6610

export NXF_APPTAINER_CACHEDIR=/scratch/${USER}/nxf-apptainer
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache

cd "${SLURM_SUBMIT_DIR}"
nextflow run main.nf -profile explorer -resume -ansi-log false \
    --samplesheet /courses/BINF6610.202710/data/samplesheet-variant8.csv \
    --ref /courses/BINF6610.202710/data/refs/grch38-1000g/GRCh38_full_analysis_set_plus_decoy_hla.fa \
    --region chr20:1-10000000 \
    --outdir results
```

On Explorer, in your repository, `git pull`, then submit it from there:

```bash
sbatch slurm/nextflow.sbatch
squeue -u $USER
```

`squeue` shows the head job, `nf-head`, and the tasks it submits, each named `nf-` and the task's
name. Its log is `nf-head-<job id>.out`: one line per task submitted, and the error, if one fails. The
first run converts each image into one file under `/scratch/$USER/nxf-apptainer`; for the reference
solution that first run took about 31 minutes, and a rerun with every task cached took 32 seconds. With
the images already converted, a run from an empty folder took 25 minutes.

If the head job stops early because `sbatch` itself reported an error, such as
`Batch job submission failed: Unexpected message received`, that is Slurm, not your pipeline: submit
`slurm/nextflow.sbatch` again, and `-resume` carries on from the tasks that had finished.

When it has finished, copy the results and commit them, as on the laptop:

```bash
mkdir -p cluster-run-nf
cp -R results/. cluster-run-nf/
git add -f cluster-run-nf
```

### 9 · Compare the records with last week's run

Last week's run, through your image, is in `cluster-run-container/`. On Explorer, in the course
environment:

```bash
module load miniconda3/25.9.1
source activate /courses/BINF6610.202710/shared/env/binf6610
{ bcftools view -H cluster-run-container/cohort.filtered.vcf.gz | sha256sum    # week 3
  bcftools view -H cluster-run-nf/cohort.filtered.vcf.gz        | sha256sum    # week 4
} > cluster-run-nf/records-sha256.txt
cat cluster-run-nf/records-sha256.txt
```

They are the same when the two runs used the same software and the same parameters: the samplesheet,
the reference, the region, the joint-genotyping tool, and the threads `bwa mem` had — last week's
`--cpus-per-task`, and this week's `cpus` for `BWA_MEM`. The reference solution's two lines are
identical.

They do not have to match. If they differ, add one sentence saying why:
`echo "They differ because …" >> cluster-run-nf/records-sha256.txt`.

## What to submit

- **The pipeline**: `main.nf`, `modules/`, `bin/`, `nextflow.config`, `slurm/nextflow.sbatch` and
  `.gitignore`.
- **`smoke-run-nf/`** and **`cluster-run-nf/`**: each a copy of that run's `results/` folder — the
  VCF, `variants.tsv`, `samples.tsv`, the MultiQC report, `manifest.json` and `pipeline_info/`.
  `cluster-run-nf/` also holds `records-sha256.txt`.
- **`TROUBLESHOOTING.md`**: the four failures below, a few lines each — the command, what it printed,
  and the fix. Replace last week's four with this week's: the earlier ones stay in your Git history.

Do not commit `work/`: it holds a copy of every intermediate file, gigabytes of them on Explorer.

## Four failures you cause on purpose

| | Break it | Write down |
|---|---|---|
| 1 | On your laptop, stop a smoke run halfway with Ctrl-C, then run the same command with `-resume` | which tasks were `cached` and which ran again |
| 2 | In your stage-3 call only, give the reference as a queue channel — `BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)` — and run the smoke dataset | how many samples `BWA_MEM` ran, and what stopped the run, or that nothing did |
| 3 | Take the backslash off the `$` of one `\$(…)` in a script block, and run | the task's `.command.sh` and `.command.err`, read from its work folder, and what `bash .command.run` did there |
| 4 | On your **first** Explorer run, set `time = '2m'` for `HAPLOTYPECALLER` in the explorer profile before you submit | the exit status Nextflow reported, and the job's `State`, `Elapsed` and `Timelimit` in `sacct` |

Put each one back afterwards.

Number 3 behaves differently with other dollar signs, which is worth knowing: without its backslash,
a bash variable such as `\$n` stops Nextflow before any task runs, with `` `n` is not defined ``, and
`\$2` inside an `awk` program runs without an error and prints the wrong thing.

**Do number 4 on your first Explorer run**, because `-resume` never reruns a task that has finished
just because its time limit changed: `cpus`, `memory` and `time` are not part of what Nextflow
compares. So: add the two-minute limit, submit, and write down what happened; then put `1h` back and
submit again. `-resume` reuses every task that finished, and the run carries on from HaplotypeCaller.
Nextflow asks Slurm to warn it 30 seconds before a job's time limit and stops the task when the
warning comes, so read what `sacct` says rather than expecting `TIMEOUT`.

**If a breakage does not do what you expected, write that down instead.** "I aimed at X, got Y, here
is why" is a full-marks answer.

## How it is graded

**100 points, ten acceptance tests.** They are in `~/a4/tests/`, they run on your laptop against your
repository, and you run them before you submit:

```bash
bash ~/a4/tests/run_acceptance.sh ~/your-repo
```

| Pts | Test | Full marks | Partial |
|---:|---|---|---|
| 10 | the pipeline is `main.nf`, `modules/` and `bin/` | a workflow block, ten processes in `modules/`, `publish.nf` and an executable `run_manifest.sh`, `work/` and `.nextflow*` ignored | **5** — one or two of those missing |
| 10 | the head job | `slurm/nextflow.sbatch` runs `nextflow run … -profile explorer` under the course account and partition, with both image caches under `/scratch` | **5** — it runs Nextflow, but a setting is missing |
| 15 | the laptop run found the planted variants | 80 % of each smoke sample's planted SNVs in `smoke-run-nf/cohort.filtered.vcf.gz` | **10** — the VCF is there, and a sample is missing or below 80 % |
| 5 | every laptop task ran in an image | every row of `smoke-run-nf/pipeline_info/trace.txt` names its container | — |
| 10 | the Explorer run has all eight samples | the eight sample columns in `cluster-run-nf/cohort.filtered.vcf.gz` | **5** — some of them |
| 10 | every Explorer task was a Slurm job in an image | every row of `cluster-run-nf/pipeline_info/trace.txt` has a Slurm job id and an Apptainer image | **5** — some rows |
| 10 | `variants.tsv` and `samples.tsv` | in `cluster-run-nf/`, the right headers, one row per VCF record and one per sample | **5** — one of the two |
| 10 | both runs' `manifest.json` | name, version, platform, executor and samples right, and the VCF's checksum matches the committed VCF | **5** — one of the two runs |
| 10 | the records compared with week 3 | two checksums in `records-sha256.txt`, the same, or different with a sentence | **5** — one checksum, or no sentence |
| 10 | `TROUBLESHOOTING.md` | all four, with evidence | **5** — two or three |

Nothing is graded on the biology, and your records do not have to match last week's.

## What this costs in wall clock

- The laptop run: 4 to 5 minutes, and about as long again for each rerun that is not cached.
- The first Explorer run: about 30 minutes once it starts, a lot of it converting images; a rerun
  with `-resume`: a minute or less, when nothing changed.
- Failure 4: part of your first Explorer run, and one resubmission.
