# Troubleshooting: four failures caused on purpose

*AI Citation: I used Claude (Sonnet 5.5) to guide me through the commands and to explain and expand on the errors. The outputs below are from my own runs.*

## 1. Ctrl-C in the middle of a run (laptop)

Command: `snakemake --profile profiles/laptop --config samplesheet=smoke/samplesheet.csv ref=smoke/smoke.fa region=smoke_1mb`

I pressed Ctrl-C about 8 seconds into the run. Snakemake printed `Terminating processes on user request, this might take some time.` and `WorkflowError: At least one job did not complete successfully.` That run had planned 14 jobs. I expected the rerun to fail with an error telling me to add `--rerun-incomplete`. It didn't: Ctrl-C was a clean stop. AS a result, Snakemake deleted the half-written files itself. The same command then ran 11 jobs (3 had already finished) and printed `11 of 11 steps (100%) done`.

Fix: I reran the same command and no fix was needed. 

## 2. A log: with no {sample} (laptop)

Command: `snakemake --profile profiles/laptop -n --config samplesheet=smoke/samplesheet.csv ref=smoke/smoke.fa region=smoke_1mb`

I removed `{sample}` from the log path of `bwa_mem` and Snakemake printed: `RuleException ... Not all output, log and benchmark files of rule bwa_mem contain the same wildcards.`

Why: `bwa_mem` runs once per sample -->  a log path without `{sample}` is the same file for every sample and the jobs would overwrite each other.

Fix: I put `"logs/bwa_mem/{sample}.log"` back into the code block.

## 3. Deleting both wildcard_constraints (laptop)

Command: the same `snakemake -n` command as failure 2.

I deleted the `wildcard_constraints:` from `fastp_paired` and `fastp_single`. Snakemake printed: `AmbiguousRuleException: Rules fastp_single and fastp_paired are ambiguous for the file work/trim/smoke_01_R1.trim.fastq.gz.`

Why: Error printed because both rules could make that file and Snakemake won't choose.

Fix: I put both wildcard_constraints back into the code block.

## 4. No Apptainer on Explorer

I deleted `software-deployment-method: apptainer` from `profiles/explorer/profile.yaml` and submitted the head job (job 11146828). The following were the outputs: 

- Rule that failed: `fastqc` (and `fastp_paired`).
- Exit status: `FAILED`, exit code 1, in `.snakemake/slurm_logs/rule_fastqc/NA10851/11146880.log`.
- The rule's own log, `logs/fastqc/NA10851.log`, said `fastqc: command not found`.

Why: with no Apptainer --> the tools are not on compute node.

Fix: `git checkout profiles/explorer/profile.yaml`, then I resubmitted (job 11147007). `validate` ran again; dry run said `Software environment definition has changed since last execution`.
