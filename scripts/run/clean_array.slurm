#!/bin/bash --norc
#SBATCH --account=p_csb_meiler
#SBATCH --partition=batch
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=2:00:00
#SBATCH --job-name=clean-arr
#SBATCH --output=logs/clean_%A_%a.out
#SBATCH --error=logs/clean_%A_%a.err

# Clean one PDB per array task using Rosetta's clean_pdb.py
# Submit with: sbatch --array=1-271%50 clean_array.slurm

set -euo pipefail

WORKDIR="/panfs/accrepfs.vampire/data/p_csb_meiler/agarwm5/protein_ideal_test/benchmarking"
MERGED="$WORKDIR/merged"
CLEANED="$WORKDIR/cleaned"
CLEAN_SCRIPT="/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/tools/protein_tools/scripts/clean_pdb.py"

mkdir -p "$CLEANED"

mapfile -t PDBS < <(ls "$MERGED"/*.pdb | sort)
IDX=$((SLURM_ARRAY_TASK_ID - 1))

if (( IDX < 0 || IDX >= ${#PDBS[@]} )); then
    echo "No work for task $SLURM_ARRAY_TASK_ID"
    exit 0
fi

pdb="${PDBS[$IDX]}"
base=$(basename "$pdb")
stem="${base%.pdb}"

# Skip if already cleaned
if [[ -f "$CLEANED/${stem}.pdb" ]]; then
    echo "SKIP: $stem already cleaned"
    exit 0
fi

# Get unique chain IDs
mapfile -t CHAINS < <(
    awk '/^ATOM/{c=substr($0,22,1); if(c==" ") c="_"; print toupper(c)}' "$pdb" | sort -u
)

if (( ${#CHAINS[@]} == 0 )); then
    echo "SKIP: $stem (no ATOM records)"
    exit 0
fi

echo "CLEAN: $stem  chains: ${CHAINS[*]}"

tmpdir="$(mktemp -d "$CLEANED/.tmp_${stem}_XXXX")"

for ch in "${CHAINS[@]}"; do
    ( cd "$tmpdir" && python "$CLEAN_SCRIPT" "$pdb" "$ch" > /dev/null 2>&1 ) || true
done

# Merge cleaned chains
python3 - "$tmpdir" "$CLEANED/${stem}.pdb" "${CHAINS[@]}" <<'PY'
import sys, os, glob
tmp = sys.argv[1]
out = sys.argv[2]
chains = sys.argv[3:]

serial = 1
with open(out, 'w') as fo:
    for ch in chains:
        files = sorted(glob.glob(os.path.join(tmp, f"*_{ch}.pdb")))
        if not files:
            continue
        with open(files[0]) as f:
            for line in f:
                if not (line.startswith("ATOM") or line.startswith("HETATM")):
                    continue
                line = f"{line[:6]}{serial:5d}{line[11:]}"
                fo.write(line.rstrip("\n") + "\n")
                serial += 1
        fo.write("TER\n")
    fo.write("END\n")
PY

rm -rf "$tmpdir"
echo "Done: $CLEANED/${stem}.pdb"
