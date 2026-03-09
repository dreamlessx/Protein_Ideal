#!/bin/bash --norc
#SBATCH --account=p_meiler_acc
#SBATCH --partition=batch_gpu
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:nvidia_l40s:1
#SBATCH --mem=32G
#SBATCH --time=06:00:00
#SBATCH --job-name=green_amber
#SBATCH --array=1-257%10
#SBATCH --output=logs/green_amber_%A_%a.out
#SBATCH --error=logs/green_amber_%A_%a.err

# Green benchmarking pipeline: Standalone AMBER relaxation
# Relaxes AF unrelaxed + Boltz predictions using AF2.3.2's AMBER module (GPU-accelerated OpenMM)
# Matches Blue's amber_relax.slurm protocol exactly for fair comparison
#
# Submit with: sbatch green_amber.slurm

set -uo pipefail

BASE="/panfs/accrepfs.vampire/data/p_csb_meiler/agarwm5/protein_ideal_test/benchmarking"
DIRLIST="${BASE}/af_dirlist.txt"
SCRIPT="${BASE}/green_amber_relax.py"
AF2_MINICONDA="/sb/apps/alphafold232/miniconda3"

mkdir -p "${BASE}/logs" 2>/dev/null || true

# ========================= TARGET SELECTION =========================
CALCDIR=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$DIRLIST")

if [[ -z "$CALCDIR" ]]; then
    echo "ERROR: Could not read directory for task $SLURM_ARRAY_TASK_ID"
    exit 1
fi

TARGET=$(basename "$CALCDIR")
echo "Task $SLURM_ARRAY_TASK_ID: $TARGET (AMBER relaxation)"
echo "Node: $SLURM_JOB_NODELIST"

# ========================= ACTIVATE AF2.3.2 CONDA ENV =========================
source "$AF2_MINICONDA/bin/activate" af232
export LD_LIBRARY_PATH="${AF2_MINICONDA}/envs/af232/lib:${LD_LIBRARY_PATH:-}"

# ========================= RUN AMBER RELAXATION =========================
python "$SCRIPT" "$CALCDIR"

echo "Done: $TARGET"
find "$CALCDIR/amber_out" -name "relaxed.pdb" 2>/dev/null | wc -l
