#!/bin/bash --norc
#SBATCH --account=p_csb_meiler
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=48:00:00
#SBATCH --job-name=relax-finish
#SBATCH --output=logs/relax_finish_%A_%a.out
#SBATCH --error=logs/relax_finish_%A_%a.err
#SBATCH --array=1-1%10

set -euo pipefail

ROOT="/data/p_csb_meiler/agarwm5/test"
RELAX="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/source/bin/relax.linuxgccrelease"
DB="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/database"

mkdir -p "$ROOT/../scripts/logs"

# ======================= DEFINE 6 PROTOCOL/WEIGHTS COMBOS =======================
declare -A CFG
CFG[cartesian_beta]="-relax:cartesian -beta_nov16 -score:weights beta_nov16_cart"
CFG[cartesian_ref15]="-relax:cartesian -score:weights ref2015_cart"
CFG[dualspace_beta]="-relax:dualspace -beta_nov16 -score:weights beta_nov16_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths"
CFG[dualspace_ref15]="-relax:dualspace -score:weights ref2015_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths"
CFG[normal_beta]="-beta_nov16 -score:weights beta_nov16"
CFG[normal_ref15]="-score:weights ref2015"

PROTOCOLS=("cartesian_beta" "cartesian_ref15" "dualspace_beta" "dualspace_ref15" "normal_beta" "normal_ref15")
NUM_REPLICATES=5

# ======================= BUILD LIST OF ALL INCOMPLETE JOBS =======================
echo "Building job list..."

declare -a JOBS  # Each element: "pdb_path|protocol|replicate"

# CRITICAL: Find ONLY original prediction files, NOT files in relax/ directories
mapfile -t AF_PDBS < <(find "$ROOT" -type f -path "*/AF/ranked_*.pdb" -not -path "*/relax/*" | sort)
mapfile -t BOLTZ_PDBS < <(find "$ROOT" -type f -path "*/Boltz/boltz_input_model_*.pdb" -not -path "*/relax/*" | sort)

echo "Found ${#AF_PDBS[@]} AF models"
echo "Found ${#BOLTZ_PDBS[@]} Boltz models"

# Function to add jobs for a PDB file
add_jobs_for_pdb() {
    local pdb_path="$1"
    local source_type="$2"  # "AF" or "Boltz"
    
    local pdb_basename=$(basename "$pdb_path" .pdb)
    local protein_dir=$(dirname "$(dirname "$pdb_path")")
    
    # Output directory structure: PROTEIN/relax/AF/ranked_X/ or PROTEIN/relax/Boltz/boltz_X/
    local relax_base="$protein_dir/relax/$source_type/$pdb_basename"
    
    # Check each protocol and replicate
    for protocol in "${PROTOCOLS[@]}"; do
        local protocol_dir="$relax_base/$protocol"
        
        for rep in $(seq 1 $NUM_REPLICATES); do
            local output_file="$protocol_dir/${pdb_basename}_r${rep}.pdb.gz"
            
            # Only add if this replicate doesn't exist
            if [[ ! -f "$output_file" ]]; then
                JOBS+=("$pdb_path|$protocol|$rep")
            fi
        done
    done
}

# Add jobs for all AF models
for pdb in "${AF_PDBS[@]}"; do
    add_jobs_for_pdb "$pdb" "AF"
done

# Add jobs for all Boltz models
for pdb in "${BOLTZ_PDBS[@]}"; do
    add_jobs_for_pdb "$pdb" "Boltz"
done

echo "Total incomplete jobs: ${#JOBS[@]}"

# ======================= GET THIS TASK'S ASSIGNMENT =======================
IDX=$((SLURM_ARRAY_TASK_ID - 1))

if [[ $IDX -lt 0 || $IDX -ge ${#JOBS[@]} ]]; then
    echo "No work for task $SLURM_ARRAY_TASK_ID (only ${#JOBS[@]} jobs found)"
    exit 0
fi

JOB="${JOBS[$IDX]}"
IFS='|' read -r PDB PROTOCOL REPLICATE <<< "$JOB"

PDB_BASENAME="$(basename "$PDB" .pdb)"
PDB_DIR="$(dirname "$PDB")"

# Determine source type from path
if [[ "$PDB_DIR" == */AF ]]; then
    SOURCE_TYPE="AF"
else
    SOURCE_TYPE="Boltz"
fi

# Determine protein directory
PROTEIN_DIR=$(dirname "$PDB_DIR")

# Set up output directory
RELAX_DIR="$PROTEIN_DIR/relax/$SOURCE_TYPE/$PDB_BASENAME"
PROTOCOL_DIR="$RELAX_DIR/$protocol"
mkdir -p "$PROTOCOL_DIR"

# Output file
OUTPUT="$PROTOCOL_DIR/${PDB_BASENAME}_r${REPLICATE}.pdb.gz"

echo "========================================"
echo "Task $SLURM_ARRAY_TASK_ID"
echo "PDB: $PDB_BASENAME"
echo "Protocol: $PROTOCOL"
echo "Replicate: $REPLICATE"
echo "Input: $PDB"
echo "Output: $OUTPUT"
echo "========================================"

# Skip if already exists
if [[ -f "$OUTPUT" ]]; then
    echo "Output already exists, skipping..."
    exit 0
fi

# ======================= RUN RELAX =======================
cd "$PROTOCOL_DIR"

# Build command - no -out:file:gz flag (not supported by Rosetta 3.15)
CMD="$RELAX -database $DB -in:file:s $PDB -nstruct 1 -out:file:scorefile relax_${PDB_BASENAME}.fasc ${CFG[$PROTOCOL]} -out:prefix ${PDB_BASENAME}_r${REPLICATE}_"

echo "Running: $CMD"
eval $CMD

# Rosetta creates uncompressed .pdb file
UNCOMPRESSED="${PDB_BASENAME}_r${REPLICATE}_0001.pdb"

if [[ -f "$UNCOMPRESSED" ]]; then
    echo "✓ Rosetta created: $UNCOMPRESSED"
    
    # Compress it
    gzip "$UNCOMPRESSED"
    
    # Move compressed file to expected location
    if [[ -f "${UNCOMPRESSED}.gz" ]]; then
        mv "${UNCOMPRESSED}.gz" "$OUTPUT"
        echo "✓ Created: $OUTPUT"
    else
        echo "✗ ERROR: Compression failed"
        exit 1
    fi
else
    echo "✗ ERROR: Expected Rosetta output not found: $UNCOMPRESSED"
    ls -la
    exit 1
fi

echo "========================================"
echo "Completed successfully"
echo "========================================"
