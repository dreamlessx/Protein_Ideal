#!/bin/bash
#SBATCH --job-name=boltz_pi
#SBATCH --account=p_meiler_acc
#SBATCH --partition=batch_gpu
#SBATCH --gres=gpu:nvidia_l40s:1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=256G
#SBATCH --time=2-00:00:00
#SBATCH --output=logs/boltz_%A_%a.out
#SBATCH --error=logs/boltz_%A_%a.err

# Boltz-1 Array Job for Protein_Ideal pipeline
# Submit with: sbatch --array=1-265%10 boltz_array.slurm

set -euo pipefail

DIRLIST_FILE="/panfs/accrepfs.vampire/data/p_csb_meiler/agarwm5/protein_ideal_test/benchmarking/af_dirlist.txt"
BOLTZ_MINICONDA="/sb/apps/boltz1-v0.4.1/miniconda3"

BOLTZ_SAMPLES="${BOLTZ_SAMPLES:-5}"
BOLTZ_RECYCLES="${BOLTZ_RECYCLES:-10}"
BOLTZ_STEPS="${BOLTZ_STEPS:-200}"
BOLTZ_CACHE="${BOLTZ_CACHE:-$HOME/.boltz}"
FORCE="${FORCE:-0}"

CALCDIR=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$DIRLIST_FILE")

if [[ -z "$CALCDIR" ]]; then
    echo "ERROR: Could not read directory for task $SLURM_ARRAY_TASK_ID"
    exit 1
fi

TARGET=$(basename "$CALCDIR")
cd "$CALCDIR"

FASTA_BASENAME="boltz_input.fasta"
[[ -s "$FASTA_BASENAME" ]] || FASTA_BASENAME="sequence.fasta"
[[ -s "$FASTA_BASENAME" ]] || { echo "No FASTA in $CALCDIR"; exit 2; }

echo "Task $SLURM_ARRAY_TASK_ID -> $TARGET ($FASTA_BASENAME)"

BOLTZ_OUT="./boltz_out_dir"

# Check for skip unless FORCE=1
if [[ "$FORCE" != "1" ]] && [[ -d "$BOLTZ_OUT" ]]; then
    count=$(find "$BOLTZ_OUT" -name "*.pdb" -type f 2>/dev/null | wc -l)
    if [[ "$count" -ge 5 ]]; then
        echo "Output exists ($count PDBs) and FORCE!=1, skipping."
        exit 0
    fi
fi

# Quick header sanity check
if ! grep -q '^>[A-Z]|PROTEIN|' "$FASTA_BASENAME" 2>/dev/null; then
    echo "WARNING: FASTA may not have proper Boltz format (>X|PROTEIN|)"
fi

source "$BOLTZ_MINICONDA/bin/activate" boltz1
export LD_LIBRARY_PATH="$BOLTZ_MINICONDA/envs/boltz1/lib:${LD_LIBRARY_PATH:-}"

echo "Starting Boltz prediction..."
boltz predict "$FASTA_BASENAME" \
    --use_msa_server \
    --recycling_steps "$BOLTZ_RECYCLES" \
    --sampling_steps "$BOLTZ_STEPS" \
    --diffusion_samples "$BOLTZ_SAMPLES" \
    --out_dir "$BOLTZ_OUT" \
    --cache "$BOLTZ_CACHE"

echo "Boltz prediction complete!"
find "$BOLTZ_OUT" -name "*.pdb" -type f | wc -l
