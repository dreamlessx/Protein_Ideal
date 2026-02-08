# Lab Notebook - BM5.5 Full Benchmark Run

## 2025-02-07: Pipeline Initialization and Data Preparation

### Step 0: Download BM5.5 Dataset

- Downloaded `benchmark5.5.tgz` from Weng Lab (Zlab, UMass Medical School)
- Extracted 271 protein-protein complexes
- Merged bound receptor + ligand PDB files into single complex PDBs
- Location: `benchmarking/merged/` (271 `.pdb` files)

### Step 1: Clean PDBs with Rosetta

- Initial attempt: serial `clean_pdbs.sh` (SLURM job 8824321)
  - Stuck on first PDB (`BENC.pdb.gz`) for 43+ minutes
  - Cancelled and replaced with array job approach
- Resubmitted as: `clean_array.slurm` (SLURM job 8824833, array 1-271, 50 concurrent)
  - Each task cleans one PDB using Rosetta `clean_pdb.py`
  - Tasks complete in 1-2 seconds each
  - **Status**: 60/271 completed as of 23:30 UTC, rest pending (Priority queue)
  - No errors observed in completed tasks
  - Output: `benchmarking/cleaned/` (40 `.pdb` files verified so far)

### Step 2: Download FASTA Sequences

- Used `scripts/data_preparation/download_fastas.py`
- **Bug fix required**: Added `from __future__ import annotations` for Python 3.9 compatibility
  (`str | None` type hints require Python 3.10+ without the future import)

Results breakdown:
- **262/271**: Downloaded from RCSB primary endpoint (`rcsb.org/fasta/entry/{PDB}`)
  with fallbacks to RCSB legacy endpoint and PDBe. Rate-limited at 0.15s between requests.
- **2 failed (obsolete PDBs)**: 1A2K, 3RVW
- **4 skipped (non-standard IDs)**: BAAD, BOYV, BP57, CP57
- **3 pre-existing**: 1AK4, 1AKJ, 1AVX (from initial pipeline testing)

#### Resolution of 2 Obsolete PDB Entries

| BM5.5 ID | Replacement PDB | Obsolete Date | Method |
|----------|----------------|---------------|--------|
| 1A2K | 5BXQ | 2023-03-01 | Queried RCSB entry API for superseding entry, downloaded FASTA from 5BXQ |
| 3RVW | 5VPG | 2022-04-27 | Queried RCSB entry API for superseding entry, downloaded FASTA from 5VPG |

Files saved under original BM5.5 IDs (e.g., `1A2K.fasta` contains 5BXQ sequences).

**Caveat**: Replacement structures may have different sequences, additional chains, or
different chain IDs. RMSD comparisons against BM5.5 bound structures should account for this.

#### Resolution of 4 Non-Standard BM5.5 Identifiers

These IDs start with letters (not digits), so they are not valid PDB accession codes.
Sequences were extracted directly from ATOM records in `merged/{ID}.pdb`.

| BM5.5 ID | Chains | Total Residues | Method |
|----------|--------|----------------|--------|
| BAAD | A (264aa), D (152aa) | 416 | ATOM parsing, 3-to-1 AA conversion |
| BOYV | B (274aa), I (104aa) | 378 | ATOM parsing, 3-to-1 AA conversion |
| BP57 | C (90aa), D (90aa), P (105aa) | 285 | ATOM parsing, 3-to-1 AA conversion |
| CP57 | I (90aa), J (90aa), P (105aa) | 285 | ATOM parsing, 3-to-1 AA conversion |

Conversion rules: standard 20 amino acids + MSE->M, HSD/HSE/HSP->H, non-standard->X.

**Caveat**: ATOM-derived sequences may differ from canonical (missing density, modified residues).

### Step 3: Organize FASTAs

- Copied each `{ID}.fasta` to `benchmarking/data/{ID}/sequence.fasta`
- 271/271 directories created and populated

### Step 4: Prepare Boltz Input

- Generated `boltz_input.fasta` for each target
- Reformatted FASTA headers to Boltz-1 format: `>{CHAIN}|PROTEIN|`
- 271/271 Boltz input files created

### Step 5: Submit AlphaFold 2.3.2 Predictions

- SLURM job: **8824491** (array 1-271, 10 concurrent tasks)
- Script: `benchmarking/af_array.slurm`
- Resources: A6000 GPU, 40GB RAM, 6 CPUs, 48h walltime
- Account: `csb_gpu_acc`, partition: `batch_gpu`
- **Bug fix**: `LD_LIBRARY_PATH` unbound variable with `set -u`. Fixed with `${LD_LIBRARY_PATH:-}`.
- **Disk management**: Added post-prediction cleanup (delete MSAs, pickles, intermediate PDBs;
  keep only ranked PDBs and `ranking_debug.json`)
- Auto-detects monomer vs multimer based on sequence count in FASTA
- **Status**: Tasks 1-10 running (~58 min, in MSA search phase), 11-271 pending

### Step 6: Submit Boltz-1 v0.4.1 Predictions

- SLURM job: **8824492** (array 1-271, 10 concurrent tasks)
- Script: `benchmarking/boltz_array.slurm`
- Resources: L40S GPU, 256GB RAM, 1 CPU, 2-day walltime
- Account: `p_meiler_acc`, partition: `batch_gpu`
- Parameters: 5 diffusion samples, 10 recycling steps, 200 sampling steps, MSA server enabled
- **Status**: All 271 tasks pending (Priority queue)

### Data Committed to GitHub

- `data/fasta/`: 271 FASTA files + `fasta_download_log.csv`
- `data/boltz_input/`: 271 Boltz-formatted FASTAs
- `data/bm55_pdb_list.txt`: 271 BM5.5 PDB IDs
- `data/af_dirlist.txt`: 271 target directory paths for SLURM arrays

### Disk Usage

- Working directory: 3.7 GB (well under 30 GB limit)
- AF cleanup script will manage disk as predictions complete

---

## 2025-02-08: AlphaFold Failure Analysis and Resubmission

### AF Job 8824491 Results (partial run)

- **5 targets completed successfully**: 1A2K, 1ACB, 1AK4, 1AVX, 1AY7
  - Each produced 5 ranked PDBs + ranking_debug.json (~2 MB per target after cleanup)
- **2 targets failed**:
  - **Task 3 (1AHW)**: OOM at 40 GB (3-chain complex, 633 residues). MaxRSS: ~40 GB.
  - **Task 6 (1ATN)**: AMBER relaxation crash - `ValueError: Amber minimization can only be
    performed on proteins with well-defined residues. This protein contains at least one
    residue with no atoms.` Completed all 5 models but crashed during GPU relaxation.
- **10 tasks cancelled mid-run** (were in MSA/prediction phase when job cancelled):
  Tasks 5, 9-17. Partial outputs cleaned.

### Script Fixes Applied

1. **Memory**: Increased from 40 GB to 64 GB (`#SBATCH --mem=64G`)
   - 1AHW OOMed at exactly 40 GB. Larger multimer complexes need more RAM.
2. **Removed `--use_gpu_relax`** from both monomer and multimer AF runs.
   - Rationale: AMBER relaxation is not needed since we apply our own Rosetta relaxation
     (6 protocols x 5 replicates). Removing it also avoids the AMBER crash on complexes
     with empty residues (1ATN failure).
   - The ranked PDB output will now be unrelaxed AF predictions.
   - Note: The 5 already-completed targets (1A2K, 1ACB, 1AK4, 1AVX, 1AY7) used AMBER
     relaxation. This is a minor inconsistency but acceptable since Rosetta relaxation
     is applied uniformly afterward.

### Resubmission

- New SLURM job: **8825835** (array 1-271, 10 concurrent)
- Previously completed targets will be auto-skipped (checks for ranking_debug.json)
- Failed/cancelled targets had partial outputs cleaned before resubmission
- Clean PDB job (8824833): 140/271 completed, 181-271 still pending
- Boltz job (8824492): all 271 still pending
- Disk usage: 6.7 GB

---

## Pending Steps

- **Step 7**: Organize AF + Boltz predictions (depends on Steps 5+6 completing)
- **Step 8**: Submit Rosetta relaxation (6 protocols x 5 replicates)
- **Step 9**: MolProbity validation
- **Step 10**: Collect RMSD + energy metrics
