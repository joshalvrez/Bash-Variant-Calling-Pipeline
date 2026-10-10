#!/usr/bin/env bash
set -euo pipefail
printf 'chrom\tpos\tref\talt\tqual\tfilter\n' > variants.tsv
bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%QUAL\t%FILTER\n' "$1" >> variants.tsv
