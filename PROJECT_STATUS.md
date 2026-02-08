# Project Status

## Overview

Protein-Protein Complex Relaxation Benchmark using Docking Benchmark 5.5 (BM5.5).
Benchmarking AlphaFold 2.3.2 and Boltz-1 predictions against experimental crystal structures,
with Rosetta relaxation across 6 protocols.

**Lab**: Meiler Lab, Vanderbilt University
**Cluster**: ACCRE (csb_gpu_acc)
**Funding**: ARPA-H alphavirus vaccine development

## Dataset: PP Docking Benchmark 5.5

- **Total complexes in BM5.5**: 271
- **FASTA sequences obtained**: 271/271 (see [FASTA Acquisition Notes](#fasta-acquisition-notes))
- **Boltz input prepared**: 271/271

### Previous Runs (Original Pipeline)

- **Successfully predicted (AF + Boltz)**: 111 targets
  - `af_completed/`: 66 targets (fully done)
  - `afset/`: 45 targets (Boltz done, AF in progress)
- **Relaxation benchmark subset**: 20 proteins (in `test/`)

### Full BM5.5 Run (Current - protein_ideal_test/)

- **Working directory**: `protein_ideal_test/benchmarking/`
- **Targets prepared**: 271
- **AlphaFold SLURM**: Job 8824491 (array 1-271, 10 concurrent)
- **Boltz-1 SLURM**: Job 8824492 (array 1-271, 10 concurrent)
- **Clean PDBs SLURM**: Job 8824321

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

### Full BM5.5 Prediction (271 targets) - IN PROGRESS

| Step | Status | SLURM Job | Notes |
|------|--------|-----------|-------|
| 0. Download BM5.5 | Done | - | 271 complexes from benchmark5.5.tgz |
| 1. Clean PDBs | Running | 8824321 | Rosetta clean_pdb.py on 271 merged PDBs |
| 2. Download FASTAs | Done | - | 262 RCSB + 2 obsolete replacements + 4 PDB-extracted + 3 pre-existing |
| 3. Organize FASTAs | Done | - | 271 data/{ID}/sequence.fasta |
| 4. Prepare Boltz input | Done | - | 271 data/{ID}/boltz_input.fasta |
| 5. AlphaFold 2.3.2 | Running | 8824491 | Array 1-271, 10 concurrent, A6000 GPUs |
| 6. Boltz-1 v0.4.1 | Pending | 8824492 | Array 1-271, 10 concurrent, L40S GPUs |
| 7. Organize predictions | Waiting | - | Depends on 5+6 |
| 8. Rosetta relaxation | Waiting | - | 6 protocols x 5 replicates |
| 9. MolProbity validation | Waiting | - | Phenix + reduce |
| 10. Collect metrics | Waiting | - | PyMOL RMSD + Rosetta energies |

## Relaxation Protocols

6 protocols, 5 replicates each:

| Protocol | Rosetta Flags |
|----------|---------------|
| cartesian_beta | `-relax:cartesian -beta_nov16 -score:weights beta_nov16_cart` |
| cartesian_ref15 | `-relax:cartesian -score:weights ref2015_cart` |
| dualspace_beta | `-relax:dualspace -beta_nov16 -score:weights beta_nov16_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| dualspace_ref15 | `-relax:dualspace -score:weights ref2015_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| normal_beta | `-beta_nov16 -score:weights beta_nov16` |
| normal_ref15 | `-score:weights ref2015` |

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
│       ├── merged/           # 271 merged complex PDBs
│       ├── cleaned/          # Rosetta-cleaned PDBs (in progress)
│       ├── fasta/            # 271 downloaded FASTAs
│       ├── data/             # 271 per-PDB directories (sequence.fasta + boltz_input.fasta)
│       ├── af_dirlist.txt    # 271 target paths for SLURM arrays
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
- [ ] MolProbity validation on full 271-target run
- [ ] ProteinBusters validation
- [ ] Statistical analysis and figures
- [ ] Manuscript preparation

## Related Repositories

- [Protein_Relax_Pipeline](https://github.com/dreamlessx/Protein_Relax_Pipeline) - Contains the 20-protein test subset with all 6,820 structures
