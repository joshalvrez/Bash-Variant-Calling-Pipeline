# variant-call — tools pipeline runs, at the versions the course conda environment has, so that switching from the environment to this image changes nothing about the software.
FROM mambaorg/micromamba:2.0.5-ubuntu24.04

# conda-forge and bioconda only. The seven pins are what
#   conda env export -p /courses/BINF6610.202710/shared/env/binf6610 --no-builds
# prints for these tools. git is not in that environment; it is added here,
# pinned, because stage 9 runs `git rev-parse` to record the commit.
#
# The clean is on the same RUN as the install, so the downloaded packages and
# the channel index never become part of the image.
RUN micromamba install -y -n base \
      -c conda-forge -c bioconda --override-channels \
      bwa=0.7.19 \
      samtools=1.24 \
      bcftools=1.24 \
      gatk4=4.6.2.0 \
      fastqc=0.12.1 \
      fastp=1.3.7 \
      multiqc=1.35 \
      git=2.47.1 \
 && micromamba clean --all --yes

# micromamba's base environment is not on PATH for a non-login shell, and a
# container command is not a login shell.
ENV PATH=/opt/conda/bin:$PATH

# Docker runs the container as this user. Apptainer ignores the line and runs as whoever started it.
USER mambauser
