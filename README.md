# Protein-Protein Complex Relaxation Benchmark: From Scratch

A complete, step-by-step guide to reproducing the protein-protein complex structure prediction and relaxation benchmark using the Protein-Protein Docking Benchmark 5.5 (BM5.5).

This document traces every script, validates each step, and provides verification checkpoints so you can confirm correctness at each stage.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Step 0: Download BM5.5 Dataset](#2-step-0-download-bm55-dataset)
3. [Step 1: Clean PDB Structures](#3-step-1-clean-pdb-structures)
4. [Step 2: Download FASTA Sequences](#4-step-2-download-fasta-sequences)
5. [Step 3: Organize FASTAs](#5-step-3-organize-fastas)
6. [Step 4: Prepare Boltz-1 Input](#6-step-4-prepare-boltz-1-input)
7. [Step 5: Run AlphaFold 2.3.2](#7-step-5-run-alphafold-232)
8. [Step 6: Run Boltz-1](#8-step-6-run-boltz-1)
9. [Step 7: Organize Predictions for Relaxation](#9-step-7-organize-predictions-for-relaxation)
10. [Step 8: Run Rosetta Relaxation](#10-step-8-run-rosetta-relaxation)
11. [Step 9: MolProbity Validation](#11-step-9-molprobity-validation)
12. [Step 10: Collect Metrics](#12-step-10-collect-metrics)
13. [Pipeline Audit](#13-pipeline-audit)
14. [Troubleshooting](#14-troubleshooting)

---

## 1. Prerequisites

### Software Requirements

| Software | Version | Installation |
|----------|---------|-------------|
| Python | 3.10+ | System or conda |
| AlphaFold | 2.3.2 | [GitHub](https://github.com/deepmind/alphafold) or cluster module |
| Boltz-1 | 0.4.1 | `pip install boltz` or cluster module |
| Rosetta | 3.15 | [RosettaCommons](https://www.rosettacommons.org/) |
| Phenix | Latest | [Phenix](https://www.phenix-online.org/) |
| Reduce | Latest | Included with Phenix or [SBGrid](https://sbgrid.org/) |
| PyMOL | 2.x+ | [PyMOL](https://pymol.org/) |
| requests | Latest | `pip install requests` |

### ACCRE-Specific Setup (Vanderbilt)

```bash
# AlphaFold 2.3.2
AF2_MINICONDA=/sb/apps/alphafold232/miniconda3
AF2_REPO=/sb/apps/alphafold232/alphafold
AF2_DATADIR=/csbtmp/alphafold-data.230

# Boltz-1 v0.4.1
BOLTZ_MINICONDA=/sb/apps/boltz1-v0.4.1/miniconda3

# Rosetta 3.14
RELAX=/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/source/bin/relax.linuxgccrelease
ROSETTA_DB=/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/database
CLEAN_SCRIPT=/data/p_csb_meiler/apps/rosetta/rosetta-3.15/main/tools/protein_tools/scripts/clean_pdb.py

# MolProbity (SBGrid)
REDUCE=/programs/x86_64-linux/system/sbgrid_bin/reduce
PHENIX=/programs/x86_64-linux/system/sbgrid_bin/phenix.molprobity
```

### Directory Structure

Create your working directory:
```bash
mkdir -p benchmarking/{merged,cleaned,fasta,data,structures,test}
cd benchmarking
```

---

## 2. Step 0: Download BM5.5 Dataset

### Source

The Protein-Protein Docking Benchmark 5.5 is maintained by the Weng Lab at UMass Medical School.

**Download page:** https://zlab.umassmed.edu/benchmark/

### What to Download

The benchmark provides:
- **Bound structures** — crystal structures of the complex
- **Unbound structures** — individual partner structures crystallized separately
- **Metadata** — complex categories (Antibody-Antigen, Enzyme-Inhibitor, etc.)

### Download Steps

```bash
# Download the benchmark tables and structures
# The exact URL may change; check the Weng Lab benchmark page
wget https://zlab.umassmed.edu/benchmark/benchmark5.5.tgz
tar -xzf benchmark5.5.tgz

# The archive contains structures in the format:
#   {PDBID}_l_b.pdb  — Ligand, bound conformation
#   {PDBID}_l_u.pdb  — Ligand, unbound conformation
#   {PDBID}_r_b.pdb  — Receptor, bound conformation
#   {PDBID}_r_u.pdb  — Receptor, unbound conformation
```

**Naming convention:**
| Suffix | Meaning |
|--------|---------|
| `_l_` | Ligand (smaller binding partner) |
| `_r_` | Receptor (larger binding partner) |
| `_b` | Bound conformation (from the complex crystal) |
| `_u` | Unbound conformation (separate crystal structure) |

### Create Merged Complexes

For this benchmark, we need the **complete complex** structures (both chains together). If you downloaded the split bound structures, merge them:

```bash
# Move split structures to structures/ for reference
mv benchmark5.5/structures/* structures/

# Create merged complexes from bound structures
for pdb_id in $(ls structures/*_r_b.pdb | sed 's/.*\///' | sed 's/_r_b.pdb//'); do
    cat "structures/${pdb_id}_r_b.pdb" "structures/${pdb_id}_l_b.pdb" | \
        grep -E '^(ATOM|HETATM|TER)' > "merged/${pdb_id}.pdb"
    echo "END" >> "merged/${pdb_id}.pdb"
done
```

Alternatively, download the full complex PDB files directly from RCSB:
```bash
# For each PDB ID in the benchmark
for pdb_id in $(cat benchmark5.5/pdb_list.txt); do
    wget -q "https://files.rcsb.org/download/${pdb_id}.pdb" -O "merged/${pdb_id}.pdb"
    sleep 0.2  # Be polite to RCSB
done
```

### Verification Checkpoint

```bash
# Should have 257 PDB files (BM5.5 = 162 rigid + 60 medium + 35 difficult)
ls merged/*.pdb | wc -l
# Expected: 257

# Each PDB should have ATOM records with multiple chains
grep -c '^ATOM' merged/1AK4.pdb
# Expected: several thousand lines

# Check chain IDs present
awk '/^ATOM/{print substr($0,22,1)}' merged/1AK4.pdb | sort -u
# Expected: A, D (or similar multi-chain output)
```

---

## 3. Step 1: Clean PDB Structures

### Script: `clean_pdbs.sh`

**What it does:**
1. For each PDB in `merged/`, extracts unique chain IDs
2. Runs Rosetta's `clean_pdb.py` on each chain individually
3. Merges cleaned chains into a single PDB with proper TER records
4. Renumbers atom serials sequentially

**Why this step exists:**
- Rosetta's `clean_pdb.py` standardizes atom naming to Rosetta conventions
- Removes HETATM records (water, ligands, ions)
- Fixes non-standard residue naming
- Required for Rosetta relaxation to work correctly

### Run

```bash
bash scripts/clean_pdbs.sh merged/ cleaned/ $CLEAN_SCRIPT
```

### Script Audit

**Input:** `merged/*.pdb` (raw PDB files from RCSB/BM5.5)
**Output:** `cleaned/{PDBID}.pdb` (one file per complex, all chains merged)

**Potential issues identified:**
- Chain ID `" "` (space) is mapped to `"_"` for Rosetta compatibility — this is correct behavior
- The script uses a temporary directory per PDB and cleans up after — safe
- Atom serial renumbering starts at 1 per file — correct
- Only ATOM and HETATM lines are kept — intentional (removes REMARK, HEADER, etc.)

**Edge cases:**
- PDBs with no ATOM records are skipped (logged as `[SKIP]`)
- If Rosetta's `clean_pdb.py` fails on a chain, that chain will be missing from output (check logs)

### Verification Checkpoint

```bash
# Should have same count as merged/
ls cleaned/*.pdb | wc -l
# Expected: same as merged/

# Each cleaned PDB should have TER between chains and END at the bottom
tail -5 cleaned/1AK4.pdb
# Expected: ATOM lines, then TER, then END

# Check that atom serials are sequential starting from 1
head -1 cleaned/1AK4.pdb
# Expected: ATOM      1 ...

# Compare chain count (should be preserved)
awk '/^ATOM/{print substr($0,22,1)}' cleaned/1AK4.pdb | sort -u
# Expected: same chains as in merged/1AK4.pdb
```

---

## 4. Step 2: Download FASTA Sequences

### Script: `download_fastas.py`

**What it does:**
1. Scans `merged/` for PDB files
2. Extracts 4-character PDB IDs from filenames
3. Downloads FASTA sequences from RCSB (with fallback to PDBe)
4. Handles obsolete entries by looking up replacement PDB IDs
5. Logs all results to `fasta_download_log.csv`

**Why not extract sequences from the PDB files directly?**
- RCSB FASTA includes all chains with proper headers
- Headers contain chain IDs needed for Boltz format conversion
- More reliable than parsing PDB ATOM records for sequence

### Run

```bash
python3 scripts/download_fastas.py merged/ fasta/
```

### Script Audit

**Input:** `merged/` directory with PDB files
**Output:** `fasta/{PDBID}.fasta` + `fasta/fasta_download_log.csv`

**Endpoint priority:**
1. `https://www.rcsb.org/fasta/entry/{PDB}` (primary)
2. `https://www.rcsb.org/pdb/download/downloadFastaFiles.do?...` (fallback)
3. `https://www.ebi.ac.uk/pdbe/entry/pdb/{PDB}/fasta` (PDBe fallback)

**Retry logic:** 2 retries per endpoint with exponential backoff (1.5^i seconds)
**Rate limiting:** 0.15s delay between PDB IDs (polite to servers)
**Obsolete handling:** If all endpoints fail, checks RCSB entry API for replacement ID

**Known special cases from our run:**
- `1A2K`, `3RVW` — obsolete PDB IDs; FASTAs downloaded from replacement entries (5BXQ, 5VPG)
- 4 non-standard IDs: `BAAD`, `BOYV`, `BP57`, `CP57` — sequences extracted from ATOM records

**DNA/RNA exclusion policy:** DNA/RNA chains are excluded from all prediction FASTAs.
BM5.5 is a protein-protein docking benchmark; neither AlphaFold nor Boltz supports
nucleic acid prediction. Targets with DNA in the crystal structure (3P57, 1H9D) have
their FASTAs filtered to protein chains only.

### Verification Checkpoint

```bash
# Check download count
grep -c 'ok' fasta/fasta_download_log.csv
# Expected: ~260-266

# Check failures
grep 'fail' fasta/fasta_download_log.csv
# Expected: 0-3 failures

# Verify FASTA format (should start with >)
head -2 fasta/1AK4.fasta
# Expected:
# >1AK4_1|Chains A, B|...
# MNGKII...

# Check that multi-chain complexes have multiple > headers
grep -c '^>' fasta/1AK4.fasta
# Expected: 2+ (one per chain group)
```

---

## 5. Step 3: Organize FASTAs

### Script: `organize_fastas.py`

**What it does:**
1. Takes flat directory of `{PDBID}.fasta` files
2. Creates one subdirectory per PDB ID under `data/`
3. Copies (or moves) the FASTA file into the subdirectory
4. Optionally renames it (e.g., to `sequence.fasta`)

### Run

```bash
python3 scripts/organize_fastas.py fasta/ data/ --rename sequence.fasta
```

### Script Audit

**Input:** `fasta/*.fasta`
**Output:** `data/{PDBID}/sequence.fasta`

**Behavior:**
- PDB ID extracted from filename stem (uppercased)
- Creates directory if it doesn't exist
- Skips existing files unless `--overwrite` is passed
- Copies by default, `--move` flag deletes source after copy

**No issues identified.** This is a straightforward file organizer.

### Verification Checkpoint

```bash
# Should have one directory per successfully downloaded FASTA
ls data/ | wc -l
# Expected: ~260-266

# Each directory should have sequence.fasta
ls data/1AK4/sequence.fasta
# Expected: exists

# Verify content matches original
diff fasta/1AK4.fasta data/1AK4/sequence.fasta
# Expected: no differences
```

---

## 6. Step 4: Prepare Boltz-1 Input

### Script: `prepare_boltz_fastas.py`

**What it does:**
1. Reads `data/*/sequence.fasta` files
2. Parses chain IDs from RCSB FASTA headers
3. Rewrites each sequence with Boltz-compatible headers: `>{CHAIN}|PROTEIN|`
4. Outputs `boltz_input.fasta` in each subdirectory

**Why this is needed:**
Boltz-1 requires a specific FASTA format where each chain header contains:
- The chain letter
- The molecule type (`PROTEIN`)
- Separated by pipes

Standard RCSB headers look like: `>1AK4_1|Chains A, B|CYCLOPHILIN A|Homo sapiens`
Boltz needs: `>A|PROTEIN|`

### Run

```bash
python3 scripts/prepare_boltz_fastas.py data/
```

### Script Audit

**Input:** `data/*/sequence.fasta`
**Output:** `data/*/boltz_input.fasta`

**Chain parsing logic:**
1. Looks for `Chain[s] A, B, C` pattern in header (regex)
2. Fallback: splits on `|`, takes first char of second field
3. Last resort: defaults to chain `A`

**Known behavior:**
- If RCSB header says `Chains A, B` (homo-dimer with identical chains), the script writes both `>A|PROTEIN|` and `>B|PROTEIN|` with the same sequence — this is correct for Boltz multimer input
- Single-chain entries get a single `>A|PROTEIN|` header

**Potential issue:** If a header has an unusual format that doesn't match the regex, it falls back to `A`. This could produce incorrect chain assignments for some entries. Verify output manually for critical targets.

### Verification Checkpoint

```bash
# Check that boltz_input.fasta was created
ls data/1AK4/boltz_input.fasta
# Expected: exists

# Verify Boltz format
head -4 data/1AK4/boltz_input.fasta
# Expected:
# >A|PROTEIN|
# MNGKII...
# >D|PROTEIN|
# PIVQNL...

# Verify chain count matches sequence.fasta
grep -c '^>' data/1AK4/sequence.fasta
grep -c '^>' data/1AK4/boltz_input.fasta
# Expected: should match (or be equal/greater if chains are split)

# Validate ALL Boltz FASTAs have correct format
for f in data/*/boltz_input.fasta; do
    if ! grep -q '|PROTEIN|' "$f"; then
        echo "BAD: $f"
    fi
done
# Expected: no output (all valid)
```

---

## 7. Step 5: Run AlphaFold 2.3.2

### Scripts: `af_array.slurm` / `af_array_highmem.slurm`

**What they do:**
- Submit SLURM GPU jobs to run AlphaFold 2.3.2
- Auto-detect monomer vs multimer based on sequence count
- Produce 10 models per target: 5 AMBER-relaxed (`ranked_*.pdb`) + 5 unrelaxed (`unrelaxed_model_*.pdb`)
- AMBER relaxation treated as 7th relaxation protocol (alongside 6 Rosetta protocols)
- Skip completed targets (completion guard checks for `ranking_debug.json`)
- Clean up intermediates (MSAs, pickles) to manage disk usage

### Run (Array Job)

```bash
# Standard (64GB RAM, covers most targets)
sbatch --array=1-257%10 scripts/run/af_array.slurm

# High-memory (128GB RAM, for large multimer complexes)
sbatch --array=<TASK_IDS> scripts/run/af_array_highmem.slurm
```

### Script Audit: `af_array.slurm`

**Resources:** 1 node, 6 tasks, 1 A6000 GPU, 64GB RAM, 48h
**FASTA selection:** Prefers `sequence.fasta` over `boltz_input.fasta`
**Preset detection:** Counts `>` lines; if >1 → multimer, else monomer
**Output:** `af_out/sequence/ranked_{0-4}.pdb` (AMBER-relaxed) + `af_out/sequence/unrelaxed_model_*.pdb` (raw predictions)

**Key flags:**
- `--nouse_gpu_relax` — runs AMBER relaxation on CPU (avoids GPU memory issues)
- `--models_to_relax=all` — AMBER-relaxes all 5 ranked models (not just best)
- `--max_template_date=9999-12-31` — allows all templates (no date cutoff)
- Monomer: uses `pdb70` database
- Multimer: uses `pdb_seqres` + `uniprot`, `num_multimer_predictions_per_model=1`

**Database preset:** Full databases (equivalent to `--db_preset=full_dbs`) with `reduced_dbs`
fallback on HHblits failure. Primary uses HHblits for BFD/UniRef30 searches; fallback uses
jackhmmer with small_bfd. The `run_af()` function wraps the prediction call and retries
with `--db_preset=reduced_dbs --small_bfd_database_path=...` if full_dbs fails.

**AMBER safety:** If AMBER relaxation crashes but unrelaxed models exist, the script
preserves unrelaxed output instead of deleting everything during the reduced_dbs retry.

**Database paths (ACCRE, `/csbtmp/alphafold-data.230/`):**
- `uniref90/uniref90.fasta`
- `mgnify/mgy_clusters_2022_05.fa`
- `uniref30/UniRef30_2021_03`
- `bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt`
- `pdb70/pdb70`
- `pdb_mmcif/mmcif_files/`
- `pdb_mmcif/obsolete.dat`

**Known OOM targets at 64GB (require 128GB highmem script):**
1AHW, 1ATN, 1DFJ, 1DQJ, 1E6J, 1FC2, 1IRA, 1JWH, 1MLC (all large multimer complexes)

### Expected Output

After cleanup, 10 models per target are retained:
```
data/{PDBID}/af_out/
└── sequence/
    ├── ranked_0.pdb              # Best AMBER-relaxed model (0-indexed)
    ├── ranked_1.pdb
    ├── ranked_2.pdb
    ├── ranked_3.pdb
    ├── ranked_4.pdb              # 5th AMBER-relaxed model
    ├── unrelaxed_model_1_*.pdb   # Raw AF prediction (1-indexed, AF convention)
    ├── unrelaxed_model_2_*.pdb
    ├── unrelaxed_model_3_*.pdb
    ├── unrelaxed_model_4_*.pdb
    ├── unrelaxed_model_5_*.pdb
    └── ranking_debug.json        # Maps ranked (0-indexed) to model (1-indexed)
```

**Numbering note**: AlphaFold uses 0-indexed `ranked_*.pdb` (ordered by confidence) and
1-indexed `unrelaxed_model_*` (unordered). The `ranking_debug.json` file maps between them.
For example, `ranked_0.pdb` may correspond to `unrelaxed_model_3` if model 3 scored highest.

Intermediate files removed by cleanup: MSAs, feature pickles, result pickles,
`relaxed_model_*.pdb` (duplicates of ranked PDBs), timings.

### Verification Checkpoint

```bash
# Check how many targets have ranking_debug.json (completion marker)
completed=0
for d in data/*/af_out/*/; do
    if [ -f "$d/ranking_debug.json" ]; then
        completed=$((completed + 1))
    fi
done
echo "AlphaFold complete: $completed"
# Expected: 257/257 when all jobs finish

# Verify a specific prediction
ls data/1AK4/af_out/sequence/ranked_*.pdb | wc -l
# Expected: 5

# Check model quality (ranking_debug.json shows pLDDT/pTM scores)
cat data/1AK4/af_out/sequence/ranking_debug.json | python3 -m json.tool | head -10
```

---

## 8. Step 6: Run Boltz-1

### Scripts: `boltz_array.slurm` / `boltz_single.slurm`

**What they do:**
- Run Boltz-1 v0.4.1 structure prediction
- Use MSA server for fast multiple sequence alignment
- Produce 5 diffusion samples per target

### Run (Array Job)

```bash
# Count targets
N=$(ls -d data/*/ | wc -l)

# Submit array job
sbatch --array=1-${N} scripts/boltz_array.slurm
```

Or for a single target:
```bash
sbatch --chdir=data/1AK4 scripts/boltz_single.slurm boltz_input.fasta
```

### Script Audit: `boltz_array.slurm`

**Resources:** 1 node, 1 CPU, 1 L40S GPU, 256GB RAM, 2 days
**FASTA selection:** Prefers `boltz_input.fasta` over `sequence.fasta`
**Header validation:** Checks that all headers match `>X|PROTEIN|` format

**Key parameters:**
- `diffusion_samples=5` — generates 5 models
- `recycling_steps=10` — structure refinement iterations
- `sampling_steps=200` — diffusion sampling steps
- `output_format=pdb` — outputs PDB files (not mmCIF)
- `use_msa_server` — uses ColabFold MSA server instead of local databases

**Output format:** `--output_format pdb` (PDB files, not mmCIF)
**Skip guard:** Checks for existing `boltz_model_*.pdb` files; skips if >= 5 found
**Force re-run:** Set `FORCE=1` environment variable

**Potential issues:**
- 256GB RAM is very high; Boltz typically needs 16-64GB. This is set conservatively.
- `--use_msa_server` requires internet access from compute nodes (may be blocked on some clusters)
- The MSA server can be slow or rate-limited during peak usage

### Expected Output

```
data/{PDBID}/boltz_out_dir/
└── boltz_results_boltz_input/
    ├── predictions/boltz_input/
    │   ├── boltz_input_model_0.pdb
    │   ├── boltz_input_model_1.pdb
    │   ├── boltz_input_model_2.pdb
    │   ├── boltz_input_model_3.pdb
    │   └── boltz_input_model_4.pdb
    ├── msa/                           # Generated MSAs
    └── processed/                     # Processed features
```

### Verification Checkpoint

```bash
# Check how many targets have Boltz models
completed=0
for d in data/*/boltz_out_dir/; do
    count=$(find "$d" -name 'boltz_input_model_*.pdb' -o -name 'boltz_model_*.pdb' 2>/dev/null | wc -l)
    if [ "$count" -ge 1 ]; then
        completed=$((completed + 1))
    fi
done
echo "Boltz complete: $completed"
# Expected: 248/257 (9 targets OOM on all GPUs, >3000 residues)

# Verify a specific prediction
find data/1AK4/boltz_out_dir -name '*.pdb' | wc -l
# Expected: 5
```

---

## 9. Step 7: Organize Predictions for Relaxation

### Manual Step (no script — do this manually)

Before running relaxation, predictions need to be organized into the `test/` directory structure:

```bash
for pdb_id in $(ls data/); do
    # Skip if no predictions
    af_count=$(ls data/$pdb_id/af_out/sequence/ranked_*.pdb 2>/dev/null | wc -l)
    boltz_count=$(find data/$pdb_id/boltz_out_dir -name 'boltz_input_model_*.pdb' 2>/dev/null | wc -l)

    if [ "$af_count" -lt 5 ] && [ "$boltz_count" -lt 5 ]; then
        echo "SKIP: $pdb_id (AF=$af_count, Boltz=$boltz_count)"
        continue
    fi

    mkdir -p test/$pdb_id/AF test/$pdb_id/Boltz

    # Copy crystal structure
    if [ -f cleaned/$pdb_id.pdb ]; then
        cp cleaned/$pdb_id.pdb test/$pdb_id/$pdb_id.pdb
    fi

    # Copy AF predictions
    cp data/$pdb_id/af_out/sequence/ranked_*.pdb test/$pdb_id/AF/ 2>/dev/null

    # Copy Boltz predictions
    find data/$pdb_id/boltz_out_dir -name 'boltz_input_model_*.pdb' \
        -exec cp {} test/$pdb_id/Boltz/ \; 2>/dev/null
done
```

### Verification Checkpoint

```bash
# Check structure
ls test/1AK4/
# Expected: 1AK4.pdb  AF/  Boltz/

ls test/1AK4/AF/
# Expected: ranked_0.pdb through ranked_4.pdb

ls test/1AK4/Boltz/
# Expected: boltz_input_model_0.pdb through boltz_input_model_4.pdb
```

---

## 10. Step 8: Run Relaxation (7 Protocols)

### Overview

7 relaxation protocols total: 1 AMBER (computed during AF prediction) + 6 Rosetta.

### Protocol 1: AMBER Relaxation (AlphaFold Native)

AMBER relaxation via OpenMM is performed during AlphaFold prediction (Step 5):
- **Force field**: AMBER ff14SB
- **Energy tolerance**: 2.39 kcal/mol
- **Position restraint stiffness**: 10.0 kcal/mol/A^2
- **Compute**: CPU (`--nouse_gpu_relax`)
- **Output**: `ranked_*.pdb` files (already generated in Step 5)

No separate script needed — AMBER relaxation is built into AlphaFold's `--models_to_relax=all`.

### Protocols 2-7: Rosetta Relaxation

### Script: `relax_predictions.slurm`

**What it does:**
1. For each PDB directory in `test/`:
   - Finds the crystal structure PDB
   - Runs 6 relaxation protocols x 5 replicates = 30 relaxed structures
2. Each replicate uses `-nstruct 1` with a different suffix (`_r1` through `_r5`)

### The 6 Rosetta Protocols

| Key | Protocol | Scoring Function | Rosetta Flags |
|-----|----------|-----------------|---------------|
| `cart_beta` | Cartesian | beta_nov16 | `-relax:cartesian -beta_nov16 -score:weights beta_nov16_cart` |
| `cart_ref15` | Cartesian | ref2015 | `-relax:cartesian -score:weights ref2015_cart` |
| `dual_beta` | Dualspace | beta_nov16 | `-relax:dualspace -beta_nov16 -score:weights beta_nov16_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| `dual_ref15` | Dualspace | ref2015 | `-relax:dualspace -score:weights ref2015_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| `norm_beta` | Normal FastRelax | beta_nov16 | `-beta_nov16 -score:weights beta_nov16` |
| `norm_ref15` | Normal FastRelax | ref2015 | `-score:weights ref2015` |

### Run

```bash
# Crystal structure relaxation
N=$(ls -d test/*/ | wc -l)
sbatch --array=1-${N} scripts/relax_predictions.slurm
```

For AI prediction relaxation, the script needs to be modified to iterate over AF and Boltz models within each PDB directory. The extended version (used in our pipeline) does:

```bash
# For each PDB in test/:
#   For each source (AF, Boltz):
#     For each model (5 models):
#       For each protocol (6 protocols):
#         For each replicate (5 replicates):
#           Run Rosetta relax → test/{PDB}/relax/{source}/{model}/{protocol}/
```

### Script Audit

**Resources:** 1 node, 1 CPU, 4GB RAM, 48h
**No GPU required** — Rosetta relax is CPU-only

**Common Rosetta flags:**
- `-ignore_zero_occupancy false` — processes all atoms regardless of occupancy
- `-nstruct 1` — one structure per run (replicates via suffix)
- `-no_nstruct_label` — don't add `_0001` to output filename
- `-out:pdb_gz` — gzip output (saves disk space)
- `-flip_HNQ` — optimize His/Asn/Gln hydrogen placement
- `-fa_max_dis 9.0` — maximum interaction distance for scoring
- `-optimization:default_max_cycles 200` — convergence iterations

**Potential issues:**
- 48h timeout: a single PDB with 6 protocols x 5 replicates = 30 runs. Each relax takes 5-60 minutes depending on size. Large complexes (>800 residues) may timeout.
- 4GB RAM is tight for large complexes. May need 8-16GB for >600 residues.
- The script uses `${CFG[$key]}` without quoting — this works because the values have no spaces in critical positions, but it's technically fragile.

### Expected Output

```
test/{PDBID}/
├── cartesian_beta/
│   ├── {PDBID}_r1.pdb.gz through _r5.pdb.gz
│   ├── log/
│   │   └── {PDBID}_cart_beta_r1.log through _r5.log
│   └── relax.fasc
├── cartesian_ref15/
│   └── [same structure]
├── dualspace_beta/
├── dualspace_ref15/
├── normal_beta/
└── normal_ref15/
```

For AI predictions:
```
test/{PDBID}/relax/
├── AF/
│   ├── ranked_0/
│   │   ├── cartesian_beta/ranked_0_r1.pdb.gz ... _r5.pdb.gz
│   │   ├── cartesian_ref15/
│   │   ├── dualspace_beta/
│   │   ├── dualspace_ref15/
│   │   ├── normal_beta/
│   │   └── normal_ref15/
│   ├── ranked_1/
│   └── ... (ranked_2 through ranked_4)
└── Boltz/
    ├── boltz_input_model_0/
    └── ... (model_1 through model_4)
```

### Verification Checkpoint

```bash
# Count relaxed structures for a single PDB (crystal only)
find test/1AK4/ -maxdepth 2 -name '*.pdb.gz' | wc -l
# Expected: 30 (6 protocols x 5 replicates)

# Count relaxed structures including AI predictions
find test/1AK4/relax/ -name '*.pdb.gz' | wc -l
# Expected: 300 (10 models x 6 protocols x 5 replicates)

# Verify a relaxation log looks normal (check for "Total weighted score")
tail -5 test/1AK4/cartesian_beta/log/1AK4_cart_beta_r1.log
# Expected: should end with score information, no errors

# Check that .fasc files contain scores
head -3 test/1AK4/cartesian_beta/relax.fasc
# Expected: SCORE: header line followed by data
```

---

## 11. Step 9: MolProbity Validation

### Script: `run_molprobity.sh`

**What it does:**
1. For each PDB in the test set:
   - Validates the experimental crystal structure
   - Validates 5 raw AlphaFold predictions
   - Validates 5 raw Boltz predictions
   - Validates all relaxed structures (30 crystal + 300 prediction relaxations)
2. Outputs per-protein CSV files with 16+ metrics per structure
3. Supports resume (skips already-validated structures)

### Run

```bash
bash scripts/run_molprobity.sh test/ molprobity_results/
```

### Script Audit

**Dependencies:** `reduce` (hydrogen addition) + `phenix.molprobity` (validation)

**Process per structure:**
1. Decompress `.pdb.gz` if needed
2. Add hydrogens with `reduce -FLIP -Quiet` (try without `-FLIP` if that fails)
3. Run `phenix.molprobity input_H.pdb keep_hydrogens=True` with 600s timeout
4. Parse `molprobity.out` for metrics
5. Write to per-protein CSV

**Metrics collected:**

| Metric | Description | Good Values |
|--------|-------------|-------------|
| Clashscore | All-atom steric clashes per 1000 atoms | < 10 |
| Ramachandran Favored | % residues in favored regions | > 95% |
| Ramachandran Outliers | % residues in outlier regions | < 0.5% |
| Rotamer Outliers | % side-chain rotamer outliers | < 2% |
| C-beta Deviations | Backbone geometry deviations | < 5 |
| Bond RMSZ | Bond length deviation from ideal | < 1.5 |
| Angle RMSZ | Bond angle deviation from ideal | < 1.5 |
| MolProbity Score | Combined quality metric | < 2.0 |

**Potential issues:**
- `reduce` may fail on structures with non-standard residues (falls back to no hydrogens)
- 600s timeout may be insufficient for very large complexes
- Parsing relies on specific `molprobity.out` format — may break with different Phenix versions

**Structures validated per PDB:** 341 total
- 1 crystal structure
- 10 raw predictions (5 AF + 5 Boltz)
- 30 crystal relaxations (6 protocols x 5 reps)
- 300 prediction relaxations (10 models x 6 protocols x 5 reps)

### Verification Checkpoint

```bash
# Check that CSV files were created
ls molprobity_results/csvs/ | wc -l
# Expected: 20 (one per PDB in test subset)

# Check line count (should be 342 = 1 header + 341 structures)
wc -l molprobity_results/csvs/1AK4_validation.csv
# Expected: 342

# Check for failures
grep -c 'FAILED' molprobity_results/csvs/1AK4_validation.csv
# Expected: 0

# Merge all CSVs for analysis
head -1 molprobity_results/csvs/$(ls molprobity_results/csvs/ | head -1) > molprobity_results/all_validation.csv
tail -n +2 -q molprobity_results/csvs/*_validation.csv >> molprobity_results/all_validation.csv
wc -l molprobity_results/all_validation.csv
# Expected: ~6821 (1 header + 341 x 20 PDBs)
```

---

## 12. Step 10: Collect Metrics

### Script: `collect_metrics.py` (PyMOL Plugin)

**What it does:**
1. Loads multiple structures into PyMOL
2. Aligns each to a reference structure (crystal)
3. Calculates C-alpha RMSD
4. Extracts Rosetta total_score from PDB REMARK lines or scorefile
5. Outputs TSV with RMSD and energy per structure

### Run (Inside PyMOL)

```python
# Load structures
load test/1AK4/1AK4.pdb, crystal
load test/1AK4/AF/ranked_0.pdb, af_ranked0
# ... load more structures

# Run the plugin
run scripts/collect_metrics.py
collect_metrics ref=crystal, sel=polymer and name CA, do_fit=1, out=metrics.tsv
```

For relaxed structures with a Rosetta scorefile:
```python
collect_metrics ref=crystal, scorefile=test/1AK4/cartesian_beta/relax.fasc, out=metrics.tsv
```

### Script Audit

**RMSD calculation:**
- Uses PyMOL's `cmd.align()` with `cycles=0` (no outlier rejection) — gives true RMSD
- Selection: `polymer and name CA` — C-alpha atoms only
- `transform=1` — performs optimal superposition before measuring

**Energy extraction priority:**
1. Check external scorefile (`.fasc` or `.sc`) if provided
2. Parse REMARK lines in PDB for `total_score`
3. Return `None` if neither found

**Output:** TSV file with columns: `object`, `rmsd_to_{ref}`, `pairs`, `energy_total_score`

**No issues identified.** This script is straightforward and correct.

### Verification Checkpoint

```bash
# Check output file
head -5 metrics.tsv
# Expected: tab-separated with RMSD values

# RMSD values should be:
# - Crystal to crystal: NaN (self)
# - Crystal relaxed: 0.5-2.0 A
# - AF predictions: 1.0-5.0 A (depends on quality)
# - AF relaxed: 1.5-6.0 A
```

---

## 13. Pipeline Audit

### Summary of Script Verification

| Step | Script | Status | Issues |
|------|--------|--------|--------|
| 0 | Download BM5.5 | Manual | URL may change; verify on Weng Lab site |
| 1 | `clean_pdbs.sh` | **PASS** | Space chain ID mapping works correctly |
| 2 | `download_fastas.py` | **PASS** | 2-3 PDB IDs may fail (obsolete/invalid) |
| 3 | `organize_fastas.py` | **PASS** | No issues |
| 4 | `prepare_boltz_fastas.py` | **PASS with caveat** | Unusual FASTA headers may default to chain A |
| 5 | `af_array.slurm` | **PASS** | 64GB RAM; 128GB highmem variant for 9 OOM targets |
| 5 | `af_array_highmem.slurm` | **PASS** | 128GB RAM for large multimer complexes |
| 6 | `boltz_array.slurm` | **PASS** | MSA server needs internet from compute node |
| 6 | `boltz_single.slurm` | **PASS** | Same MSA server caveat |
| 7 | Organize predictions | Manual | No script — documented above |
| 8 | `relax_predictions.slurm` | **PASS with caveat** | 48h may timeout for large complexes; 4GB RAM may be tight |
| 9 | `run_molprobity.sh` | **PASS** | Phenix version-dependent output parsing |
| 10 | `collect_metrics.py` | **PASS** | No issues |

### Overall Pipeline Viability: PLAUSIBLE

The pipeline is scientifically sound and technically correct. The main risks are:
1. **Resource limits** — some SLURM scripts use tight memory/time limits that may fail on large complexes
2. **External dependencies** — MSA server availability, RCSB API stability
3. **Manual steps** — Step 7 (organizing predictions) has no script and is error-prone

### Recommendations

1. Increase array job memory to 16GB for relaxation, 64GB for AlphaFold array
2. Create a script for Step 7 (organizing predictions) to eliminate manual errors
3. Add a master pipeline script that chains all steps with dependency checking
4. Add `.gitignore` for large intermediate files (MSAs, pickles)

---

## 14. Troubleshooting

### AlphaFold Fails with OOM

```
ResourceExhaustedError: OOM when allocating tensor
```
**Fix:** Increase `--mem` in SLURM script. Large complexes (>600 residues) may need 64-128GB.

### Boltz MSA Server Timeout

```
ConnectionError: MSA server not responding
```
**Fix:** Check internet access from compute nodes. If blocked, pre-compute MSAs using local databases:
```bash
boltz predict input.fasta --msa_dir ./precomputed_msas/ --output_format pdb
```

### Rosetta Relax Crashes

```
ERROR: Unable to open file
```
**Fix:** Check that the Rosetta database path (`-database`) is correct and accessible from compute nodes.

### MolProbity Parsing Returns NA

```
NA,NA,NA,NA...
```
**Fix:** Check Phenix version compatibility. The parsing regex expects specific output format from `phenix.molprobity`. Run manually and compare output format:
```bash
phenix.molprobity input.pdb keep_hydrogens=True
cat molprobity.out
```

### FASTA Download Failures

```
[FAIL] 3RVW: no FASTA found
```
**Fix:** Some PDB IDs are obsolete. Check https://www.rcsb.org/structure/{PDBID} for replacement entries. Update your PDB list accordingly.
