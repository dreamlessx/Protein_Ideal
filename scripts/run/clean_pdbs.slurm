#!/bin/bash --norc
#SBATCH --account=p_csb_meiler
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=24:00:00
#SBATCH --job-name=clean-pdbs
#SBATCH --output=logs/clean_pdbs_%j.out
#SBATCH --error=logs/clean_pdbs_%j.err

set -euo pipefail

WORKDIR="/panfs/accrepfs.vampire/data/p_csb_meiler/agarwm5/protein_ideal_test"
CLEAN_SCRIPT="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/tools/protein_tools/scripts/clean_pdb.py"

cd "$WORKDIR"
bash Protein_Ideal/scripts/data_preparation/clean_pdbs.sh benchmarking/merged benchmarking/cleaned "$CLEAN_SCRIPT"

echo "Clean complete: $(ls benchmarking/cleaned/*.pdb | wc -l) files"
