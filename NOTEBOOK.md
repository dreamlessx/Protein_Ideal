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

### Resubmission #1 (Job 8825835) - FAILED

- Submitted with `--use_gpu_relax` removed entirely from command
- **Result**: 266/271 tasks failed immediately with:
  `FATAL Flags parsing error: flag --use_gpu_relax=None: Flag --use_gpu_relax must have a value other than None.`
- AF2's absl flags require `--use_gpu_relax` to be explicitly set (boolean flag).
  Cannot omit it; must use `--nouse_gpu_relax` to disable.
- 5 tasks completed (auto-skipped, already had output from job 8824491)

### Resubmission #2 (Job 8827162)

- Fixed flag: replaced removal with `--nouse_gpu_relax` in both monomer and multimer blocks
- Memory remains at 64 GB
- Clean PDB job (8824833): **271/271 completed**
- Boltz job (8824492): all 271 still pending
- Disk usage: 665 MB (cleaned PDBs are small; AF outputs pending)

### Target List Correction: 271 -> 257

Cross-referenced our 271-entry archive against the official BM5.5 list at
https://zlab.wenglab.org/benchmark/ (162 rigid-body + 60 medium + 35 difficult = 257).

**14 entries removed** - present in the benchmark5.5.tgz archive but NOT part of BM5.5:

| Removed ID | Reason |
|-----------|--------|
| 1BGX | Not in BM5.5 (older benchmark version) |
| 1BJ1 | Not in BM5.5 (older benchmark version) |
| 1BVK | Not in BM5.5 (older benchmark version) |
| 1FSK | Not in BM5.5 (older benchmark version) |
| 1I9R | Not in BM5.5 (older benchmark version) |
| 1IQD | Not in BM5.5 (older benchmark version) |
| 1K4C | Not in BM5.5 (older benchmark version) |
| 1KXQ | Not in BM5.5 (older benchmark version) |
| 1NCA | Not in BM5.5 (older benchmark version) |
| 1NSN | Not in BM5.5 (older benchmark version) |
| 1QFW | Not in BM5.5 (older benchmark version) |
| 2HMI | Not in BM5.5 (older benchmark version) |
| 2JEL | Not in BM5.5 (older benchmark version) |
| 9QFW | Not in BM5.5 (older benchmark version) |

Deleted from: `data/`, `fasta/`, `cleaned/`, `merged/`, and GitHub `data/` directories.
Regenerated `af_dirlist.txt` and `bm55_pdb_list.txt` with 257 entries.

**4 non-standard IDs confirmed as part of BM5.5**: BAAD, BOYV, BP57, CP57.
These use benchmark-specific identifiers rather than standard PDB codes.

Final count: **253 standard PDB IDs + 4 non-standard IDs = 257 BM5.5 complexes**.

### Resubmission #3 (Jobs 8827452 / 8827453)

- AF job 8827452: array 1-257, 10 concurrent, 64 GB, `--nouse_gpu_relax`
  - 5 targets already complete (auto-skipped): 1A2K, 1ACB, 1AK4, 1AVX, 1AY7
- Boltz job 8827453: array 1-257, 10 concurrent

### AF Job 8827452 Failure Analysis

68/257 completed successfully. **9 tasks failed** (all OOM at 64 GB):

| Task | Target | Chains | Failure | MaxRSS |
|------|--------|--------|---------|--------|
| 3 | 1AHW | 3 (633 aa) | OOM | 64 GB |
| 6 | 1ATN | 2 | OOM | 64 GB |
| 18 | 1DFJ | 2 | OOM | 64 GB |
| 19 | 1DQJ | 3 | OOM | 64 GB |
| 22 | 1E6J | 3 | OOM | 64 GB |
| 34 | 1FC2 | 2 | OOM | 64 GB |
| 59 | 1IRA | 2 | OOM | 64 GB |
| 67 | 1JWH | 2 | OOM | 64 GB |
| 81 | 1MLC | 3 | OOM | 64 GB |

### Rescue Attempt #1: Jobs 8832606 / 8832608 / 8833852 - FAILED

Added `--norun_relax` flag to skip AMBER relaxation entirely. **All tasks failed immediately**:
```
FATAL Flags parsing error: Unknown command line flag 'norun_relax'
```

`--norun_relax` does not exist in AF 2.3.2. The correct flag to skip relaxation is
`--models_to_relax=none`. However, the decision was made to **keep AMBER relaxation**
since it is the AF default behavior.

### Script Updates: AMBER Relaxation on All Models

Per user request, updated AF scripts to relax ALL 5 ranked models (not just the best):
- Removed invalid `--norun_relax` flag
- Added `--models_to_relax=all` to both monomer and multimer blocks
- Kept `--nouse_gpu_relax` (runs AMBER minimization on CPU)

**Inconsistency note**: The main job 8827452 was submitted before `--models_to_relax=all`
was added. Tasks 1-91 (68 completed + 10 currently running) used the default
`--models_to_relax=best`, meaning only ranked_0.pdb is AMBER-relaxed while
ranked_1 through ranked_4 are unrelaxed. Tasks 92-257 (job 8834163) and the 9
rescue tasks (job 8834020) will have all 5 models AMBER-relaxed.

### Rescue Attempt #2: Job 8834020 (128 GB, --models_to_relax=all)

- Array tasks: 3,6,18,19,22,34,59,67,81
- Memory: 128 GB
- Script: `af_array_highmem.slurm`
- Flags: `--nouse_gpu_relax --models_to_relax=all`

### Resubmission of Tasks 92-257: Job 8834163

- Cancelled pending tasks 92-257 from job 8827452
- Resubmitted with updated `af_array.slurm` (now includes `--models_to_relax=all`)

### Design Change: 10 AF Models Per Target

Previous approach kept only AMBER-relaxed ranked PDBs (5 per target). Updated to keep
both unrelaxed and relaxed models:

- **5 `ranked_*.pdb`**: AMBER-relaxed via OpenMM (CPU)
- **5 `unrelaxed_model_*.pdb`**: Raw AF predictions, no relaxation

AMBER relaxation is now treated as one of the relaxation protocols (alongside 6 Rosetta
protocols), rather than a preprocessing step. The unrelaxed models serve as the baseline
input for all relaxation comparisons.

**Full AF reset**: Cleaned all 216 existing af_out directories (had deleted unrelaxed
models). Resubmitted all 257 targets from scratch.

### Active AF Jobs (Reset)

| Job ID | Tasks | Memory | models_to_relax | Keeps unrelaxed | Status |
|--------|-------|--------|-----------------|-----------------|--------|
| 8849349 | 248 standard tasks | 64 GB | all | Yes | Submitted |
| 8849371 | 3,6,18,19,22,34,59,67,81 | 128 GB | all | Yes | Submitted |

---

## 2025-02-09: AF Jobs Cancelled, Documentation Updates

### AF Jobs 8849349 / 8849371 Status

Both AF jobs from the full reset were cancelled. Resubmitted as:

| Job ID | Tasks | Memory | Status |
|--------|-------|--------|--------|
| 8851183 | 248 standard (excluding 9 OOM) | 64 GB | Running |
| 8851184 | 3,6,18,19,22,34,59,67,81 | 128 GB | Running |

### Boltz-1 Progress and CIF Bug Fix

- Job 8827453: 157/257 completed, rest cancelled
- **Bug found**: Script missing `--output_format pdb` — all 157 targets produced `.cif` (mmCIF)
  instead of `.pdb`. Rosetta cannot read mmCIF format.
- **Fix applied**:
  1. Converted all 785 CIF files to PDB using BioPython (`MMCIFParser` + `PDBIO`) — 0 failures
  2. Added `--output_format pdb` to `boltz_array.slurm`
  3. Updated skip guard to check for both `.cif` and `.pdb` files
- **Resubmitted**: Job **8851422** for 100 remaining targets with corrected script
- Boltz outputs are unrelaxed (native Boltz predictions, 5 models per target)

### Database Configuration Decision

Using full databases (equivalent to `--db_preset=full_dbs`) with `reduced_dbs` fallback:
- HHblits for BFD and UniRef30 searches (primary)
- `reduced_dbs` fallback using small_bfd via jackhmmer (on HHblits failure)
- 1IRA confirmed HHblits failure on titin fragments in BFD (same issue Pipeline hit on 1AHW, 1ATN)
- AF script now wraps prediction in retry: full_dbs → clean output → reduced_dbs

### AF Model Numbering Note

AlphaFold uses different numbering conventions for its output files:
- `ranked_0.pdb` through `ranked_4.pdb` — 0-indexed, ordered by model confidence
- `unrelaxed_model_1_*.pdb` through `unrelaxed_model_5_*.pdb` — 1-indexed, not ordered by confidence

The mapping between ranked and unrelaxed models is in `ranking_debug.json`. For example,
`ranked_0.pdb` may correspond to `unrelaxed_model_3_*.pdb` depending on which model scored highest.

### Documentation Updates

- Updated COMPARISON.md: Pipeline now uses full_dbs primary with reduced_dbs fallback;
  both pipelines save 10 AF models (5 relaxed + 5 unrelaxed); AMBER as 7th protocol;
  both target 257 BM5.5 complexes
- Updated README.md: 10 AF models per target, full databases, AMBER as 7th relaxation
  protocol, updated expected output structure
- Updated PROJECT_STATUS.md: 7 relaxation protocols, current job status, full_dbs config

## 2026-02-10: HHblits Fallback, Boltz OOM Analysis

### HHblits Failure on 1IRA — Fallback Added

- AF highmem job 8851184 task 59 (1IRA) failed after 43 min
- Error: HHblits titin fragments in BFD exceed 32763 residue limit
- Same issue Pipeline Claude reported on 1AHW and 1ATN
- **Fix**: Modified both `af_array.slurm` and `af_array_highmem.slurm`:
  - Changed `set -euo pipefail` to `set -uo pipefail` (removed `-e`)
  - Wrapped AF call in `run_af()` function with full_dbs/reduced_dbs modes
  - On full_dbs failure: clean partial output, retry with `--db_preset=reduced_dbs` + `small_bfd`
- Resubmitted 1IRA as job **8851737** with updated script

### Boltz OOM — Tiered GPU Strategy

**Problem**: 23/257 targets OOM on L40S (48GB VRAM) with 5 diffusion samples.

**Resolution** (3 tiers):

| Tier | GPU | Samples | Targets | Result |
|------|-----|---------|---------|--------|
| Standard | L40S 48GB | 5 | 234 targets (<1300 res) | 234/234 ✓ |
| Highmem | H100 80GB | 5 | 14 targets (1300-2200 res) | 12/14 ✓ |
| XL | H100 80GB | 1 | 11 targets (>2200 res) | 2/11 ✓ |

**Final Boltz tally: 248/257** (96.5%)
- 245 targets with 5 models
- 2 targets (1GXD, 3EO1) with 1 model
- 1 target (4GXU, 5730 res) may succeed with 1 sample on larger GPU — testing

**9 permanently OOMed targets** (all >3000 residues, AF-only):
1DE4(3042), 1K5D(3212), 1N2C(3182), 1WDW(3798), 1ZM4(3147),
3BIW(3268), 3L89(3924), 4GXU(5730), 6EY6(3624)

Created `boltz_array_highmem.slurm` for H100 targets.

### Additional HHblits Failures

- 1DQJ (task 19): HHblits titin failure, resubmitted job 8851780
- 1MLC (task 81): HHblits titin failure, resubmitted job 8854324
- 1IRA fallback **succeeded** in 1h53m with reduced_dbs

### AF Progress

First completions arriving: 32/257 standard + 1 fallback (1IRA) as of ~02:30 UTC.
All completed targets show expected 10 models (5 ranked + 5 unrelaxed).
Cleanup removes MSAs/pickles automatically. Disk: 37 GB.

---

## 2026-02-10 (cont.): Input Verification, DNA Fix, Cleanup

### Input Verification (God Claude Directive #4/#5)

Comprehensive comparison of Green's FASTA files against the authoritative set
(dreamlessx's `fasta/` folder in Protein_Relax_Pipeline, 265 files) and Blue's
active runs (`af_work/`, 257 targets).

**Green vs Authoritative (251 overlapping targets):**

| Category | Count |
|----------|-------|
| Byte-identical | 48 |
| Same sequences, different chain order | 203 |
| Truly different sequences | **0** |

Green passes with zero sequence mismatches. The 203 chain-order reversals are
cosmetic (Green uses BM5.5 receptor-first order; Auth uses RCSB chain-ID order).

6 targets in Green but not in Auth: 1A2K, 3RVW, BAAD, BOYV, BP57, CP57
(non-standard IDs or obsolete replacements without authoritative FASTAs).

14 targets in Auth but not in Green: old BM5.5 entries already excluded from
our 257-target list (1BGX, 1BJ1, 1BVK, etc.).

**Green vs Blue (257 overlapping targets):**

| Category | Count |
|----------|-------|
| Same sequences | 240 |
| Truly different | 17 |

Of 17 different: 6 are the non-standard targets (no authoritative source to
arbitrate); 11 are where Blue diverges from both Green AND the authoritative
set (Blue's FASTA generation had bugs: empty files, missing chains).

### DNA/RNA Chain Removal

Per God Claude's DNA/RNA exclusion policy (protein-only predictions), audited
all 257 targets for DNA/RNA sequences in FASTAs. Found 2 targets:

| Target | DNA chains removed | Protein chains kept |
|--------|-------------------|-------------------|
| 3P57 | 2 DNA strands (15 nt each) | p300 (111 aa) + MEF2A x6 (86 aa) |
| 1H9D | 2 DNA strands (10 nt each) | CBF-alpha x2 (131 aa) + CBF-beta x2 (133 aa) |

Both `sequence.fasta` and `boltz_input.fasta` updated for each target.
Neither target had started AF yet (3P57=task 193, 1H9D=task 49), so no
re-runs needed. The `boltz_input.fasta` files also had a bug where DNA
chains were mislabeled as `|PROTEIN|` — now fixed.

BP57 and CP57 (derived from 3P57) already had DNA stripped — no changes needed.

### Disk Cleanup

- Deleted `blue_repo_check/` temp clone of Protein_Relax_Pipeline (5.9 GB freed)
- Deleted temp verification scripts from ClaudeChat/ (fasta_comparison.sh, etc.)
- Current disk: ~28 GB (below 30 GB soft target)

### AF Progress Update

| Job | Tasks | Status |
|-----|-------|--------|
| 8851183 | 248 standard (64GB) | 29/257 complete, ~10 running |
| 8855266 | 6 highmem (128GB): 1AHW, 1ATN, 1DFJ, 1E6J, 1FC2, 1JWH | Running |
| 8854324 | 1 task: 1MLC | Complete (reduced_dbs fallback) |

HHblits fallback targets confirmed working: 1IRA, 1DQJ, 1MLC all completed
with reduced_dbs.

### Boltz Final Status

248/257 (96.5%) — no changes from earlier:
- 245 targets: 5 models (standard)
- 2 targets (1GXD, 3EO1): 1 model (H100 1-sample)
- 9 targets: permanently OOMed (>3000 residues, AF-only)

---

## 2026-02-10 (cont.): AF Progress, INSTRUCTIONS.md, Repo Restructure

### ClaudeChat Repo Restructured

ClaudeChat was restructured by Red Pro-Ops:
- Chat files moved from root to `projects/protein/`
- `CHAT_3.md` renamed to `CHAT.md` (active thread)
- `CHAT.md` renamed to `CHAT_1.md` (archived)
- New: `SYSTEM_RULES.md` at root with global rules for all instances
- Hierarchy formalized: dreamlessx → Red Pro-Ops → Workers (Blue, Green, Teal)
- Context gauge required in every status update
- Handoff notes format for low-context sessions

### AF Progress: 90/257 (35%)

| Category | Count | Notes |
|----------|-------|-------|
| Full success (10 models) | 87 | 5 ranked + 5 unrelaxed |
| AMBER failure (5 unrelaxed) | 3 | 1ATN, 1DFJ, 1FC2 |
| Currently running | 10 | Tasks 83-98 on job 8851183 |
| Pending | 157 | In SLURM queue |
| Highmem jobs | All 6 done | Job 8855266 complete |
| 1MLC (fallback) | Done | Job 8854324 complete |

AMBER failures on 1ATN, 1DFJ, 1FC2: all 5 unrelaxed models saved correctly by
the safety logic in af_array.slurm. AMBER relaxation failed (likely empty residues
or non-standard atoms), but the unrelaxed models are the baseline for Rosetta
relaxation — so these targets will have 6 protocols (Rosetta only) instead of 7.

### INSTRUCTIONS.md Created

Per Red Pro-Ops directive, created `INSTRUCTIONS.md` in Protein_Ideal repo root with:
- Role description and coordination workflow
- Full pipeline configuration (AF, Boltz, Rosetta)
- Working directory layout
- Disk management policy
- Boundaries (what Green does NOT do)

### Disk: 24 GB

Down from 28 GB after further AF cleanup. Well under 30 GB soft target.

---

## 2026-02-15: AF Near-Complete, HHblits Retries, Disk Cleanup

### AF Progress: 226/257 (88%)

Main job 8851183 completed. Results:
- 220 targets: full 10 models (5 ranked + 5 unrelaxed)
- 6 AMBER failures: 1ATN, 1DFJ, 1FC2, 2BTF, 4CPA, 5JMO (5 unrelaxed each)
- 31 targets: HHblits failure — all with `RuntimeError: HHblits failed` (titin/32763 residue limit)

### Root Cause of 31 HHblits Failures

Job 8851183 was submitted BEFORE the `reduced_dbs` fallback was added to `af_array.slurm`.
SLURM copies scripts at submission time, so modifying the script file after submission has no
effect on running/pending tasks. These 31 targets ran with the old script (no retry logic) and
failed on the first HHblits attempt.

### Resubmission: Job 9011401

Cleaned failed af_out directories (had only MSAs, no models). Resubmitted all 31 as:
```
sbatch --array=109,134,157,...,252%10 af_array.slurm
```
Job 9011401 uses the current script with full_dbs → reduced_dbs fallback.
Status: PENDING (QOSGrpGRES — GPU queue congested, 2189 pending cluster-wide).

### AMBER Failure Comparison with Blue

Blue reports 7 AMBER failures. Green confirms 6 of 7:

| Target | Blue | Green |
|--------|------|-------|
| 1ATN | AMBER fail | AMBER fail |
| 1DFJ | AMBER fail | AMBER fail |
| 1FC2 | AMBER fail | AMBER fail |
| 2BTF | AMBER fail | AMBER fail |
| 4CPA | AMBER fail | AMBER fail |
| 5JMO | AMBER fail | AMBER fail |
| 1WEJ | AMBER fail | HHblits fail (in resubmit, will check) |

### Disk Emergency and Cleanup

Disk reached 66 GB (over 50 GB hard limit). Root cause: 34 targets retained MSAs and
pickle files from failed or recently completed runs (cleanup script only runs on success).

Cleaned all intermediates across all targets:
- Removed msas/, features.pkl, result_model_*.pkl, relaxed_model_*.pdb, timings.json
- Result: 66 GB → 30 GB

### Boltz Audit (246 + 2 + 9 = 257)

Full audit confirmed Boltz outputs in `boltz_out_dir/boltz_results_boltz_input/predictions/boltz_input/`:
- 246 targets: 5 models
- 2 targets (1GXD, 3EO1): 1 model
- 9 targets: empty (permanently OOM, >3000 residues)

---

## Pending Steps
- **Step 7**: Organize AF + Boltz predictions (depends on Steps 5+6 completing)
- **Step 8**: Submit relaxation (7 protocols x 5 replicates)
  - 1 AMBER/OpenMM protocol (already computed during AF prediction as `ranked_*.pdb`)
  - 6 Rosetta protocols: cart_beta, cart_ref15, dual_beta, dual_ref15, norm_beta, norm_ref15
- **Step 9**: MolProbity validation
- **Step 10**: Collect RMSD + energy metrics
