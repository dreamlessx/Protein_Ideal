#!/bin/bash
#SBATCH --job-name=boltz-array
#SBATCH --account=p_meiler_acc
#SBATCH --partition=batch_gpu
#SBATCH --gres=gpu:nvidia_l40s:1
#SBATCH --nodes=1
#SBATCH --cpus-per-task=1
#SBATCH --mem=256G
#SBATCH --time=2-00:00:00
#SBATCH --output=/data/p_csb_meiler/agarwm5/scripts/logs/boltz_%A_%a.out
#SBATCH --error=/data/p_csb_meiler/agarwm5/scripts/logs/boltz_%A_%a.err

set -euo pipefail

# --- Paths ---
DATA_ROOT="${DATA_ROOT:-/data/p_csb_meiler/agarwm5/afset}"
BOLTZ_MINICONDA="/sb/apps/boltz1-v0.4.1/miniconda3"

# --- Knobs ---
BOLTZ_SAMPLES="${BOLTZ_SAMPLES:-5}"
BOLTZ_RECYCLES="${BOLTZ_RECYCLES:-10}"
BOLTZ_STEPS="${BOLTZ_STEPS:-200}"
BOLTZ_OUT="${BOLTZ_OUT:-./boltz_out_dir}"
BOLTZ_CACHE="${BOLTZ_CACHE:-$HOME/.boltz}"
FORCE="${FORCE:-0}"

# --- Build directory list ---
mapfile -t ALL < <(
  find "$DATA_ROOT" -mindepth 1 -maxdepth 1 -type d \
  | while read dir; do
      if [[ -f "$dir/boltz_input.fasta" ]] || [[ -f "$dir/sequence.fasta" ]]; then
        echo "$dir"
      fi
    done | sort
)

N=${#ALL[@]}
IDX=$((SLURM_ARRAY_TASK_ID-1))

if (( IDX < 0 || IDX >= N )); then
  echo "No work for task $SLURM_ARRAY_TASK_ID (have $N targets)."
  exit 0
fi

D="${ALL[$IDX]}"
FASTA_BASENAME="boltz_input.fasta"
[[ -s "$D/$FASTA_BASENAME" ]] || FASTA_BASENAME="sequence.fasta"
[[ -s "$D/$FASTA_BASENAME" ]] || { echo "No FASTA in $D"; exit 2; }

cd "$D"
echo "Task $SLURM_ARRAY_TASK_ID/$N -> $(pwd)/$FASTA_BASENAME"

# Check for skip unless FORCE=1
if [[ "$FORCE" != "1" ]] && [[ -d "$BOLTZ_OUT" ]]; then
  # Check if predictions exist
  if find "$BOLTZ_OUT" -name "*.pdb" -type f 2>/dev/null | grep -q .; then
    echo "Output exists and FORCE!=1, skipping."
    exit 0
  fi
fi

# Quick header sanity check (Boltz wants >X|PROTEIN|)
if ! grep -q '^>[A-Z]|PROTEIN|' "$FASTA_BASENAME" 2>/dev/null; then
  echo "WARNING: FASTA may not have proper Boltz format (>X|PROTEIN|)"
fi

# Activate Boltz environment
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
