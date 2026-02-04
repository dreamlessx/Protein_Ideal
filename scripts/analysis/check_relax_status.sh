#!/bin/bash
# Monitor progress of relax jobs

set -euo pipefail

ROOT="/data/p_csb_meiler/agarwm5/todo"
PROTOCOLS=("cartesian_beta" "cartesian_ref15" "dualspace_beta" "dualspace_ref15" "normal_beta" "normal_ref15")
NUM_REPLICATES=5

echo "Checking relax completion status..."
echo "=================================================="

# Find all models
mapfile -t AF_PDBS < <(find "$ROOT" -type f -path "*/AF/ranked_*.pdb" 2>/dev/null | sort)
mapfile -t BOLTZ_PDBS < <(find "$ROOT" -type f -path "*/Boltz/boltz_input_model_*.pdb" 2>/dev/null | sort)

total_expected=$((( ${#AF_PDBS[@]} + ${#BOLTZ_PDBS[@]} ) * ${#PROTOCOLS[@]} * NUM_REPLICATES))
total_complete=0
total_missing=0

# Check completion for a PDB
check_pdb() {
    local pdb_path="$1"
    local source_type="$2"
    
    local pdb_basename=$(basename "$pdb_path" .pdb)
    local protein_dir=$(dirname "$pdb_path" | sed 's|/'"$source_type"'$||')
    local relax_base="$protein_dir/relax/$source_type/$pdb_basename"
    
    local complete=0
    local missing=0
    
    for protocol in "${PROTOCOLS[@]}"; do
        local protocol_dir="$relax_base/$protocol"
        
        for rep in $(seq 1 $NUM_REPLICATES); do
            local output_file="$protocol_dir/${pdb_basename}_r${rep}.pdb.gz"
            
            if [[ -f "$output_file" ]]; then
                ((complete++))
            else
                ((missing++))
            fi
        done
    done
    
    echo "$complete $missing"
}

# Check AF models
echo "AF Models:"
echo "----------"
for pdb in "${AF_PDBS[@]}"; do
    read complete missing < <(check_pdb "$pdb" "AF")
    ((total_complete += complete))
    ((total_missing += missing))
    
    pdb_name=$(basename "$pdb" .pdb)
    expected=$((${#PROTOCOLS[@]} * NUM_REPLICATES))
    pct=$((complete * 100 / expected))
    
    if [[ $missing -eq 0 ]]; then
        echo "  ✓ $pdb_name: $complete/$expected (100%)"
    else
        echo "    $pdb_name: $complete/$expected ($pct%) - $missing missing"
    fi
done

echo ""
echo "Boltz Models:"
echo "-------------"
for pdb in "${BOLTZ_PDBS[@]}"; do
    read complete missing < <(check_pdb "$pdb" "Boltz")
    ((total_complete += complete))
    ((total_missing += missing))
    
    pdb_name=$(basename "$pdb" .pdb)
    expected=$((${#PROTOCOLS[@]} * NUM_REPLICATES))
    pct=$((complete * 100 / expected))
    
    if [[ $missing -eq 0 ]]; then
        echo "  ✓ $pdb_name: $complete/$expected (100%)"
    else
        echo "    $pdb_name: $complete/$expected ($pct%) - $missing missing"
    fi
done

echo ""
echo "=================================================="
echo "OVERALL PROGRESS:"
overall_pct=$((total_complete * 100 / total_expected))
echo "  Complete: $total_complete / $total_expected ($overall_pct%)"
echo "  Missing: $total_missing"
echo "=================================================="

# Check running jobs
echo ""
echo "SLURM Jobs:"
echo "----------"
squeue -u $USER -n relax-finish -o "%.10i %.9P %.20j %.8T %.10M %.6D" 2>/dev/null || echo "No jobs running"

echo ""
