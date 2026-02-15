# Project Status

## Overview

Protein-Protein Complex Relaxation Benchmark using Docking Benchmark 5.5 (BM5.5).
Benchmarking AlphaFold 2.3.2 and Boltz-1 predictions against experimental crystal structures,
with relaxation across 7 protocols (1 AMBER/OpenMM + 6 Rosetta).

**Lab**: Meiler Lab, Vanderbilt University
**Cluster**: ACCRE (csb_gpu_acc)
**Funding**: ARPA-H alphavirus vaccine development

## Dataset: PP Docking Benchmark 5.5

- **Total complexes in BM5.5**: 257
- **FASTA sequences obtained**: 257/257 (see [FASTA Acquisition Notes](#fasta-acquisition-notes))
- **Boltz input prepared**: 257/257

### Previous Runs (Original Pipeline)

- **Successfully predicted (AF + Boltz)**: 111 targets
  - `af_completed/`: 66 targets (fully done)
  - `afset/`: 45 targets (Boltz done, AF in progress)
- **Relaxation benchmark subset**: 20 proteins (in `test/`)

### Full BM5.5 Run (Current - protein_ideal_test/)

- **Working directory**: `protein_ideal_test/benchmarking/`
- **Targets prepared**: 257
- **Clean PDBs**: Done (257/257)
- **AlphaFold**: 226/257 complete (88%). Job 8851183 done + 8855266 (highmem, done) + 8854324 (1MLC, done) + 9011401 (31 HHblits retries, pending)
  - 220 targets: full 10 models (5 ranked + 5 unrelaxed)
  - 6 AMBER failures (1ATN, 1DFJ, 1FC2, 2BTF, 4CPA, 5JMO): 5 unrelaxed models saved
  - 31 targets: HHblits failure resubmitted with reduced_dbs fallback (job 9011401)
- **Boltz-1**: 248/257 complete (96.5%). 9 targets OOM on all GPUs (>3000 residues, AF-only)
- **AF config**: `--nouse_gpu_relax --models_to_relax=all` (AMBER relax all 5 models on CPU)
- **AF output**: 10 models per target (5 AMBER-relaxed `ranked_*.pdb` + 5 unrelaxed `unrelaxed_model_*.pdb`)
- **Database preset**: Full databases (HHblits + BFD + UniRef30), `reduced_dbs` fallback on HHblits failure
- **Input verification**: Green's FASTAs verified against authoritative set — 0 sequence mismatches (251/251)
- **DNA/RNA policy**: DNA/RNA chains excluded from all prediction FASTAs (protein-only). Fixed 3P57 and 1H9D.
- **Disk usage**: ~30 GB (cleaned from 66 GB after MSA purge; under 50 GB hard limit)

## FASTA Acquisition Notes

### Standard Downloads (262 entries)

Downloaded from RCSB primary endpoint (`rcsb.org/fasta/entry/{PDB}`) with fallbacks
to RCSB legacy endpoint and PDBe. Rate-limited at 0.15s between requests.

### Obsolete PDB Entries (2 entries)

These PDB IDs were obsoleted by RCSB and replaced:

| BM5.5 ID | Status | Replacement PDB | Obsolete Date | Resolution |
|----------|--------|----------------|---------------|------------|
| 1A2K | Obsolete | **5BXQ** | 2023-03-01 | FASTA downloaded from 5BXQ; GDP-RAN-NTF2 complex |
| 3RVW | Obsolete | **5VPG** | 2022-04-27 | FASTA downloaded from 5VPG; Der p 1 + Fab 4C1 |

**Method**: Checked RCSB entry API for replacement IDs, downloaded FASTA from
replacement entries. Files saved as original BM5.5 IDs (e.g., `1A2K.fasta`
contains 5BXQ sequences).

**Caveat**: The replacement structures may have slightly different sequences,
additional chains, or different chain IDs compared to the original BM5.5
bound structures. RMSD comparisons should account for this.

### Non-Standard BM5.5 Identifiers (4 entries)

These entries have benchmark-specific IDs that don't match standard PDB naming
(PDB IDs start with a digit; these start with letters). FASTA sequences were
extracted directly from the ATOM records in the BM5.5 bound structure PDB files.

| BM5.5 ID | Chains | Residues | Extraction Method |
|----------|--------|----------|-------------------|
| BAAD | A (264aa), D (152aa) | 416 total | ATOM record parsing, 3-letter to 1-letter conversion |
| BOYV | B (274aa), I (104aa) | 378 total | ATOM record parsing, 3-letter to 1-letter conversion |
| BP57 | C (90aa), D (90aa), P (105aa) | 285 total | ATOM record parsing, 3-letter to 1-letter conversion |
| CP57 | I (90aa), J (90aa), P (105aa) | 285 total | ATOM record parsing, 3-letter to 1-letter conversion |

**Method**: Parsed ATOM records from `merged/{ID}.pdb`, extracted unique residues
per chain using standard 3-to-1 amino acid mapping (including MSE->M, HSD/HSE/HSP->H).
Non-standard residues mapped to 'X'.

**Boltz input**: Headers reformatted to `>{CHAIN}|PROTEIN|` for Boltz-1 compatibility.

**Caveat**: Sequences extracted from ATOM records may differ from canonical
sequences (missing density regions, modified residues). These entries may need
manual verification against the original BM5.5 documentation.

### Previously Downloaded (3 entries)

1AK4, 1AKJ, 1AVX were downloaded during initial pipeline testing and skipped
during the bulk download (files already existed).

## Completion Status

### Relaxation Benchmark (20 proteins) - COMPLETE

| Category | Expected | Complete | Status |
|----------|----------|----------|--------|
| Experimental PDBs | 20 | 20 | Done |
| AlphaFold predictions (5 ranked per target) | 100 | 100 | Done |
| Boltz-1 predictions (5 models per target) | 100 | 100 | Done |
| Experimental relaxed (6 protocols x 5 reps) | 600 | 600 | Done |
| AF relaxed (5 models x 6 protocols x 5 reps) | 3,000 | 3,000 | Done |
| Boltz relaxed (5 models x 6 protocols x 5 reps) | 3,000 | 3,000 | Done |
| **Total** | **6,820** | **6,820** | **Done** |

### 20 Benchmark Proteins

```
1AK4  1AKJ  1AVX  1AY7  1AZS
1BUH  1BVN  1E6E  1EFN  1EWY
1EXB  1F51  1FCC  1GHQ  1GLA
1HCF  1JPS  1K74  1VFB  2I25
```

### Full BM5.5 Prediction (257 targets) - IN PROGRESS

| Step | Status | SLURM Job(s) | Notes |
|------|--------|-------------|-------|
| 0. Download BM5.5 | Done | - | 257 complexes (14 non-BM5.5 entries removed from archive) |
| 1. Clean PDBs | Done | 8824833 | 257/257 cleaned with Rosetta clean_pdb.py |
| 2. Download FASTAs | Done | - | 249 RCSB + 2 obsolete replacements + 4 PDB-extracted + 2 pre-existing |
| 3. Organize FASTAs | Done | - | 257 data/{ID}/sequence.fasta |
| 4. Prepare Boltz input | Done | - | 257 data/{ID}/boltz_input.fasta |
| 5. AlphaFold 2.3.2 | 226/257 (31 retrying) | 8851183 (done) + 8855266 (done) + 8854324 (done) + 9011401 (31 HHblits retries) | 6 AMBER failures, 31 HHblits failures resubmitted with fallback |
| 6. Boltz-1 v0.4.1 | Done (248/257) | - | 9 OOM targets (>3000 res), 2 targets with 1 model |
| 7. Organize predictions | Waiting | - | Depends on Step 5 completing |
| 8. Relaxation | Waiting | - | 7 protocols: 1 AMBER (done in Step 5) + 6 Rosetta x 5 replicates |
| 9. MolProbity validation | Waiting | - | Phenix + reduce |
| 10. Collect metrics | Waiting | - | PyMOL RMSD + Rosetta energies |

## Relaxation Protocols

7 protocols total (1 AMBER + 6 Rosetta), 5 replicates each for Rosetta:

| # | Protocol | Method | Notes |
|---|----------|--------|-------|
| 1 | AMBER (native) | AlphaFold OpenMM (ff14SB) | Computed during AF prediction (CPU relax) |
| 2 | cartesian_beta | Rosetta | `-relax:cartesian -beta_nov16 -score:weights beta_nov16_cart` |
| 3 | cartesian_ref15 | Rosetta | `-relax:cartesian -score:weights ref2015_cart` |
| 4 | dualspace_beta | Rosetta | `-relax:dualspace -beta_nov16 -score:weights beta_nov16_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| 5 | dualspace_ref15 | Rosetta | `-relax:dualspace -score:weights ref2015_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| 6 | normal_beta | Rosetta | `-beta_nov16 -score:weights beta_nov16` |
| 7 | normal_ref15 | Rosetta | `-score:weights ref2015` |

## Key Findings (Preliminary)

- Beta scoring function consistently outperforms ref15
- AlphaFold predictions sometimes achieve better MolProbity scores than experimental structures
- Experimental structures show ~38% improvement with relaxation
- AI predictions show ~17-20% improvement with relaxation

## Bug Fixes Applied

1. **`download_fastas.py`**: Added `from __future__ import annotations` for Python 3.9
   compatibility (`str | None` union type hints require Python 3.10+).
2. **`af_array.slurm`**: Fixed `LD_LIBRARY_PATH` unbound variable error with `set -u`
   by using `${LD_LIBRARY_PATH:-}` default expansion.
3. **AF intermediate cleanup**: Added post-prediction cleanup to `af_array.slurm` to
   delete MSAs, pickles, and intermediate PDBs (keeps only ranked PDBs and
   ranking_debug.json) to stay within 30GB disk quota.

## ACCRE Directory Layout

```
/data/p_csb_meiler/agarwm5/
├── protein_ideal_test/       # Full BM5.5 pipeline run (current)
│   ├── Protein_Ideal/        # Cloned repo
│   └── benchmarking/         # Pipeline working directory
│       ├── merged/           # 257 merged complex PDBs
│       ├── cleaned/          # Rosetta-cleaned PDBs (in progress)
│       ├── fasta/            # 257 downloaded FASTAs
│       ├── data/             # 257 per-PDB directories (sequence.fasta + boltz_input.fasta)
│       ├── af_dirlist.txt    # 257 target paths for SLURM arrays
│       ├── af_array.slurm    # AlphaFold array job
│       ├── boltz_array.slurm # Boltz-1 array job
│       └── clean_pdbs.slurm  # PDB cleaning job
├── af_completed/             # 66 targets, fully predicted (AF + Boltz)
├── afset/                    # 45 targets, AF in progress
├── test/                     # 20-protein relaxation benchmark (6,820 structures)
└── scripts/                  # Original SLURM scripts
```

## Software Versions

| Software | Version | Location on ACCRE |
|----------|---------|-------------------|
| AlphaFold | 2.3.2 | `/sb/apps/alphafold232/` |
| Boltz-1 | 0.4.1 | conda env |
| Rosetta | 3.15 | `/data/p_csb_meiler/apps/rosetta/rosetta-3.15/` |
| Python | 3.9.21 | System (pipeline scripts) |
| Python | 3.8.18 | AF2 conda env (af232) |
| CUDA | 12.6 | Driver 560.35.05 |

## Validation Pipeline (TODO)

- [ ] MolProbity validation on all 6,820 structures (20-protein subset)
- [ ] MolProbity validation on full 257-target run
- [ ] ProteinBusters validation
- [ ] Statistical analysis and figures
- [ ] Manuscript preparation

## Related Repositories

- [Protein_Relax_Pipeline](https://github.com/dreamlessx/Protein_Relax_Pipeline) - Contains the 20-protein test subset with all 6,820 structures
