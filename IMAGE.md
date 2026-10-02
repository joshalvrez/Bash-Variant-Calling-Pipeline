# IMAGE.md — what I built, and how to prove it

## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1

## The pushed image
docker.io/joshalvrez/variant-call@sha256:824302cfa9f920fe9418728e00bf20efa6ed8daf9d8659a899c42bf538d34064

To rerun this in a year, what is needed is the exact image the run used, and the heading
that gives it is **The pushed image**. The `.sif` on Explorer will be gone, because
`/scratch` is emptied every month, and the tag `1.0` could have been pointed at a different
image by then; the digest cannot change, so `apptainer pull docker://joshalvrez/variant-call@sha256:<digest>`
(what `slurm/pull.sbatch` does) fetches the same image again. The other two headings are
for the case where the registry copy is gone and the image has to be rebuilt from
`containers/Dockerfile`: **Base image** says what to start from and **Versions pinned** says
what to install, but a rebuild resolves every package I did not pin on the day it is built,
so it would give the same seven tools and not a byte-identical image.
