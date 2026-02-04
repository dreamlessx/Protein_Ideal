#!/bin/bash --norc
#SBATCH --account=p_csb_meiler
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=48:00:00
#SBATCH --job-name=relax-test
#SBATCH --output=logs/relax_test_%A_%a.out
#SBATCH --error=logs/relax_test_%A_%a.err
#SBATCH --array=1-1                 # set to 1-N at submit

set -euo pipefail

ROOT="/data/p_csb_meiler/agarwm5/test"
RELAX="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/source/bin/relax.linuxgccrelease"
DB="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/database"

mkdir -p "$ROOT/../logs"

# ======================= BUILD LIST OF ALL PDB FILES =======================
# Find all ranked_*.pdb in AF folders and boltz_input_model_*.pdb in Boltz folders
mapfile -t AF_PDBS < <(find "$ROOT" -type f -path "*/AF/ranked_*.pdb" | sort)
mapfile -t BOLTZ_PDBS < <(find "$ROOT" -type f -path "*/Boltz/boltz_input_model_*.pdb" | sort)

# Combine into single array
ALL_PDBS=("${AF_PDBS[@]}" "${BOLTZ_PDBS[@]}")

# Get this task's assignment
IDX=$((SLURM_ARRAY_TASK_ID - 1))
[[ $IDX -ge 0 && $IDX -lt ${#ALL_PDBS[@]} ]] || { 
    echo "No work for task $SLURM_ARRAY_TASK_ID (only ${#ALL_PDBS[@]} PDBs found)"; 
    exit 0; 
}

PDB="${ALL_PDBS[$IDX]}"
PDB_BASENAME="$(basename "$PDB" .pdb)"
PDB_DIR="$(dirname "$PDB")"

echo "========================================"
echo "Task $SLURM_ARRAY_TASK_ID: $PDB_BASENAME"
echo "PDB: $PDB"
echo "========================================"

# ======================= DEFINE 6 PROTOCOL/WEIGHTS COMBOS =======================
declare -A CFG
CFG[cartesian_beta]="-relax:cartesian -beta_nov16 -score:weights beta_nov16_cart"
CFG[cartesian_ref15]="-relax:cartesian -score:weights ref2015_cart"
CFG[dualspace_beta]="-relax:dualspace -beta_nov16 -score:weights beta_nov16_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths"
CFG[dualspace_ref15]="-relax:dualspace -score:weights ref2015_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths"
CFG[normal_beta]="-beta_nov16 -score:weights beta_nov16"
CFG[normal_ref15]="-score:weights ref2015"

# ======================= COMMON FLAGS =======================
COMMON_FLAGS=(
    -database "$DB"
    -s "$PDB"
    -ignore_zero_occupancy false
    -nstruct 1
    -no_nstruct_label
    -out:pdb_gz
    -flip_HNQ
    -fa_max_dis 9.0
    -optimization:default_max_cycles 200
    -out:levels all:warning
)

# ======================= RUN 5 REPLICATES PER PROTOCOL =======================
for protocol in cartesian_beta cartesian_ref15 dualspace_beta dualspace_ref15 normal_beta normal_ref15; do
    # Create output folder: test/1AK4/AF/ranked_0/cartesian_beta/
    OUT="$PDB_DIR/${PDB_BASENAME}/$protocol"
    mkdir -p "$OUT/log"
    
    echo "==> Running $protocol for $PDB_BASENAME"
    
    for r in {1..5}; do
        echo "   - replicate r${r}"
        "$RELAX" \
            "${COMMON_FLAGS[@]}" \
            ${CFG[$protocol]} \
            -out:path:all "$OUT" \
            -scorefile relax.fasc \
            -out::suffix "_r${r}" \
            >> "$OUT/log/${PDB_BASENAME}_${protocol}_r${r}.log" 2>&1
    done
done

echo "========================================"
echo "Done: $PDB_BASENAME"
echo "========================================"
