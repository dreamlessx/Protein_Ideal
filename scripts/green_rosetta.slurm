#!/bin/bash --norc
#SBATCH --account=p_csb_meiler
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=8G
#SBATCH --time=72:00:00
#SBATCH --job-name=green_rosetta
#SBATCH --array=1-257%50
#SBATCH --output=logs/green_rosetta_%A_%a.out
#SBATCH --error=logs/green_rosetta_%A_%a.err

# Green benchmarking pipeline: Rosetta relaxation
# 6 input types x 6 protocols x 5 replicates per target
# Matches Blue's rosetta_relax_v2.slurm protocol exactly for fair comparison
#
# Input types:
#   1. af_relaxed       - AF built-in AMBER relaxed (control)
#   2. af_unrelaxed     - AF unrelaxed (no AMBER)
#   3. boltz            - Boltz-1 unrelaxed (no AMBER)
#   4. amber_af         - Standalone AMBER relaxed AF unrelaxed (test)
#   5. amber_boltz      - Standalone AMBER relaxed Boltz (test)
#   6. crystal          - Experimental crystal structure
#
# Rosetta protocols:
#   cartesian_beta, cartesian_ref15, dualspace_beta,
#   dualspace_ref15, normal_beta, normal_ref15
#
# Submit with: sbatch green_rosetta.slurm

set -euo pipefail

# ========================= CONFIGURATION =========================
BASE="/panfs/accrepfs.vampire/data/p_csb_meiler/agarwm5/protein_ideal_test/benchmarking"
DIRLIST="${BASE}/af_dirlist.txt"
RELAX="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/source/bin/relax.linuxgccrelease"
DB="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/database"

mkdir -p "${BASE}/logs" 2>/dev/null || true

# ========================= TARGET SELECTION =========================
D=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$DIRLIST")

if [[ -z "$D" ]]; then
    echo "ERROR: No target found for task ID ${SLURM_ARRAY_TASK_ID}"
    exit 1
fi

TARGET=$(basename "$D")
echo "========================================"
echo "Task ${SLURM_ARRAY_TASK_ID}: ${TARGET}"
echo "Target dir: ${D}"
echo "========================================"

# ========================= CREATE af_out_unrelaxed/ WITH RANKED SYMLINKS =========================
# Maps unrelaxed model names to ranked order via ranking_debug.json
# This matches Blue's directory structure for fair comparison
if [[ ! -d "$D/af_out_unrelaxed" ]] && [[ -f "$D/AF/ranking_debug.json" ]]; then
    mkdir -p "$D/af_out_unrelaxed"
    python3 -c "
import json, os
with open('$D/AF/ranking_debug.json') as f:
    ranking = json.load(f)
order = ranking.get('order', [])
for rank, model_name in enumerate(order):
    src = os.path.join('$D', 'AF', f'unrelaxed_{model_name}.pdb')
    dst = os.path.join('$D', 'af_out_unrelaxed', f'ranked_{rank}.pdb')
    if os.path.exists(src) and not os.path.exists(dst):
        os.symlink(os.path.relpath(src, '$D/af_out_unrelaxed'), dst)
        print(f'  Linked ranked_{rank}.pdb -> {model_name}')
"
    echo "Created af_out_unrelaxed/ with ranked symlinks"
fi

# ========================= 6 ROSETTA PROTOCOLS =========================
declare -A CFG
CFG[cartesian_beta]="-relax:cartesian -beta_nov16 -score:weights beta_nov16_cart"
CFG[cartesian_ref15]="-relax:cartesian -score:weights ref2015_cart"
CFG[dualspace_beta]="-relax:dualspace -beta_nov16 -score:weights beta_nov16_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths"
CFG[dualspace_ref15]="-relax:dualspace -score:weights ref2015_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths"
CFG[normal_beta]="-beta_nov16 -score:weights beta_nov16"
CFG[normal_ref15]="-score:weights ref2015"

# ========================= COMMON FLAGS (MATCHING BLUE EXACTLY) =========================
COMMON_FLAGS=(
    -database "$DB"
    -ignore_zero_occupancy false
    -nstruct 1
    -no_nstruct_label
    -out:pdb_gz
    -flip_HNQ
    -fa_max_dis 9.0
    -optimization:default_max_cycles 200
    -out:levels all:warning
)

# ========================= COLLECT ALL INPUT PDBs =========================
shopt -s nullglob
ALL_PDBS=()
SRC_TYPES=()
MODEL_LABELS=()

# 1. AF built-in AMBER relaxed (ranked_0..4.pdb from AF/)
if [[ -d "$D/AF" ]]; then
    for f in "$D/AF"/ranked_{0,1,2,3,4}.pdb; do
        ALL_PDBS+=("$f")
        SRC_TYPES+=("af_relaxed")
        MODEL_LABELS+=("$(basename "$f" .pdb)")
    done
fi

# 2. AF unrelaxed (ranked symlinks created above)
if [[ -d "$D/af_out_unrelaxed" ]]; then
    for f in "$D/af_out_unrelaxed"/ranked_{0,1,2,3,4}.pdb; do
        ALL_PDBS+=("$f")
        SRC_TYPES+=("af_unrelaxed")
        MODEL_LABELS+=("$(basename "$f" .pdb)")
    done
fi

# 3. Boltz unrelaxed
if [[ -d "$D/Boltz" ]]; then
    for f in "$D/Boltz"/boltz_input_model_{0,1,2,3,4}.pdb; do
        ALL_PDBS+=("$f")
        SRC_TYPES+=("boltz")
        MODEL_LABELS+=("$(basename "$f" .pdb)")
    done
fi

# 4. Standalone AMBER of AF unrelaxed
if [[ -d "$D/amber_out" ]]; then
    for i in 0 1 2 3 4; do
        f="$D/amber_out/af_unrelaxed_${i}/relaxed.pdb"
        if [[ -f "$f" ]]; then
            ALL_PDBS+=("$f")
            SRC_TYPES+=("amber_af")
            MODEL_LABELS+=("ranked_${i}")
        fi
    done
fi

# 5. Standalone AMBER of Boltz
if [[ -d "$D/amber_out" ]]; then
    for i in 0 1 2 3 4; do
        f="$D/amber_out/boltz_model_${i}/relaxed.pdb"
        if [[ -f "$f" ]]; then
            ALL_PDBS+=("$f")
            SRC_TYPES+=("amber_boltz")
            MODEL_LABELS+=("model_${i}")
        fi
    done
fi

# 6. Crystal structure
CRYSTAL_PDB="$D/${TARGET}.pdb"
if [[ -f "$CRYSTAL_PDB" ]]; then
    ALL_PDBS+=("$CRYSTAL_PDB")
    SRC_TYPES+=("crystal")
    MODEL_LABELS+=("${TARGET}")
fi

shopt -u nullglob

if [[ ${#ALL_PDBS[@]} -eq 0 ]]; then
    echo "No PDBs found for $TARGET"
    exit 0
fi

echo "Found ${#ALL_PDBS[@]} input models for $TARGET"
echo "  af_relaxed:   $(printf '%s\n' "${SRC_TYPES[@]}" | grep -c '^af_relaxed$' || true)"
echo "  af_unrelaxed: $(printf '%s\n' "${SRC_TYPES[@]}" | grep -c '^af_unrelaxed$' || true)"
echo "  boltz:        $(printf '%s\n' "${SRC_TYPES[@]}" | grep -c '^boltz$' || true)"
echo "  amber_af:     $(printf '%s\n' "${SRC_TYPES[@]}" | grep -c '^amber_af$' || true)"
echo "  amber_boltz:  $(printf '%s\n' "${SRC_TYPES[@]}" | grep -c '^amber_boltz$' || true)"
echo "  crystal:      $(printf '%s\n' "${SRC_TYPES[@]}" | grep -c '^crystal$' || true)"

# ========================= RUN RELAXATION =========================
for i in "${!ALL_PDBS[@]}"; do
    pdb="${ALL_PDBS[$i]}"
    src_type="${SRC_TYPES[$i]}"
    model="${MODEL_LABELS[$i]}"

    # Build output directory name: {src_type}_{model_label}
    # Uses MODEL_LABELS to avoid collision (AMBER models all have basename "relaxed")
    OUT_BASE="$D/rosetta_out/${src_type}_${model}"

    for protocol in cartesian_beta cartesian_ref15 dualspace_beta dualspace_ref15 normal_beta normal_ref15; do
        OUT_DIR="${OUT_BASE}/${protocol}"

        # Skip if already done (5 replicates)
        if [[ -d "$OUT_DIR" ]] && [[ $(ls "$OUT_DIR"/*.pdb.gz 2>/dev/null | wc -l) -ge 5 ]]; then
            continue
        fi

        mkdir -p "$OUT_DIR/log"

        echo "==> $TARGET :: ${src_type}_${model} :: $protocol"
        for r in 1 2 3 4 5; do
            # Per-replicate skip: check if *_r${r}.pdb.gz exists
            if compgen -G "${OUT_DIR}/*_r${r}.pdb.gz" > /dev/null 2>&1; then
                echo "  Rep $r exists, skipping"
                continue
            fi

            "$RELAX" \
                "${COMMON_FLAGS[@]}" \
                -s "$pdb" \
                ${CFG[$protocol]} \
                -out:path:all "$OUT_DIR" \
                -scorefile relax.fasc \
                -out::suffix "_r${r}" \
                >> "$OUT_DIR/log/r${r}.log" 2>&1 || true
        done
    done
done

echo "========================================"
echo "Done: $TARGET"
echo "========================================"
