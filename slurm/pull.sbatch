#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -J w3-pull
#SBATCH -o pull-%j.out
set -euo pipefail

# Without this --> download cache lands in the home directory
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p "${APPTAINER_CACHEDIR}" /scratch/${USER}/containers

apptainer pull --force /scratch/${USER}/containers/variant-call.sif \
    docker://joshalvrez/variant-call@sha256:824302cfa9f920fe9418728e00bf20efa6ed8daf9d8659a899c42bf538d34064

ls -l /scratch/${USER}/containers/variant-call.sif
