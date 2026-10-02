#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -J w3-pull
#SBATCH -o pull-%j.out
#-----------------------------------------------------------------------------
# Fetch my image onto Explorer and convert it to a .sif. This is a job and not
# a command on the login node because the conversion needs several GB of memory,
# and on the login node every user's processes share one small limit.
#
# The image is named by its DIGEST, not by its tag: the tag 1.0 could be pointed
# at a different image later, the digest cannot.
#-----------------------------------------------------------------------------
set -euo pipefail

# Without this the download cache lands in the home directory, whose quota is
# fixed and small.
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p "${APPTAINER_CACHEDIR}" /scratch/${USER}/containers

apptainer pull --force /scratch/${USER}/containers/variant-call.sif \
    docker://joshalvrez/variant-call@sha256:824302cfa9f920fe9418728e00bf20efa6ed8daf9d8659a899c42bf538d34064

ls -l /scratch/${USER}/containers/variant-call.sif
