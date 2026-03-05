# Project Status

## Overview

Protein-Protein Complex Relaxation Benchmark using Docking Benchmark 5.5 (BM5.5).
Benchmarking AlphaFold 2.3.2 and Boltz-1 predictions against experimental crystal structures,
with relaxation across 7 protocols (1 AMBER/OpenMM + 6 Rosetta).

**Lab**: Meiler Lab, Vanderbilt University
**Cluster**: ACCRE (csb_gpu_acc)
**Funding**: ARPA-H alphavirus vaccine development

## Dataset: PP Docking Benchmark 5.5

- **Total complexes in BM5.5**: 257 (all active — 11 OOM targets recovered via FASTA dedup)
- **FASTA sequences obtained**: 257/257
- **Boltz input prepared**: 257/257 (11 use deduplicated unique-chain FASTAs)

### Previous Runs (Original Pipeline)

- **Successfully predicted (AF + Boltz)**: 111 targets
  - `af_completed/`: 66 targets (fully done)
  - `afset/`: 45 targets (Boltz done, AF in progress)
- **Relaxation benchmark subset**: 20 proteins (in `test/`)

### Full BM5.5 Run (Current - protein_ideal_test/)

- **Working directory**: `protein_ideal_test/benchmarking/`
- **Targets prepared**: 257
- **Clean PDBs**: Done (257/257)
- **Active benchmark**: **257 targets** (full BM5.5, no exclusions)
  - **FASTA deduplication**: 119 homo-multimeric targets deduplicated to unique sequences only
  - All FASTAs (AF + Boltz), AF predictions, and crystal structures use identical chain sets per target
  - Root cause of original 11 OOM failures: `boltz_input.fasta` listed all physical chain copies
    (quadratic attention scaling). Dedup to unique sequences resolved all OOMs on L40S 48GB
- **FASTA strategy**: Crystal-derived sequences (not UniProt full-length) — see [FASTA Strategy](#fasta-strategy-crystal-derived-vs-uniprot-full-length)
- **AlphaFold**: **257/257 complete (100%)** — 5 ranked + 5 unrelaxed per target, re-run with crystal-derived FASTAs
- **Boltz-1**: **149/257 complete, 108 re-running** with deduplicated crystal-derived FASTAs (job 9304609)
- **AF config**: `--nouse_gpu_relax --models_to_relax=all` (AMBER relax all 5 models on CPU)
- **AF output**: 10 models per target (5 AMBER-relaxed `ranked_*.pdb` + 5 unrelaxed `unrelaxed_model_*.pdb`)
- **Database preset**: Full databases (HHblits + BFD + UniRef30), `reduced_dbs` fallback on HHblits failure
- **Input verification**: Green's FASTAs verified against authoritative set — 0 sequence mismatches (251/251)
- **DNA/RNA policy**: DNA/RNA chains excluded from all prediction FASTAs (protein-only). Fixed 3P57 and 1H9D.
- **Disk usage**: ~10 GB (cleaned 31 GB of AF stderr logs; under 50 GB hard limit)

## FASTA Strategy: Crystal-Derived vs UniProt Full-Length

### The Problem

RCSB FASTA downloads provide **full-length UniProt canonical sequences**, which include residues
not resolved in the crystal structure — disordered N/C-termini, flexible loops, signal peptides,
and transmembrane domains that were removed for crystallization. These extra residues create
mismatches between the prediction input and the crystal reference used for RMSD evaluation.

When AlphaFold or Boltz predicts a structure from the full-length UniProt sequence, the resulting
model contains regions that have no counterpart in the crystal structure. RMSD calculations then
compare apples to oranges: the predicted structure covers residues 1–965 while the crystal only
resolves residues 217–965, leaving 216 residues in the prediction with no ground truth.

### Examples: UniProt vs Crystal-Derived Sequences

| Target | Chain | Crystal (resolved) | UniProt (canonical) | Extra residues | Description |
|--------|-------|--------------------|---------------------|----------------|-------------|
| **6A0Z** | A | 270 aa | 551 aa | **+281** | Influenza hemagglutinin (signal peptide + transmembrane removed) |
| **1HE8** | A | 749 aa | 965 aa | **+216** | PI3K gamma (N-terminal domain absent from crystal) |
| **1MQ8** | A | 184 aa | 291 aa | **+107** | ICAM-1 (only 2 of 5 Ig domains crystallized) |
| **1AZS** | C | 339 aa | 402 aa | **+63** | Gs-alpha (disordered termini removed) |
| **1ACB** | E | 238 aa | 245 aa | **+7** | Alpha-chymotrypsin (minor zymogen cleavage artifact) |
| **1ACB** | I | 63 aa | 70 aa | **+7** | Eglin C (N-terminal residues disordered) |
| **1BUH** | A | 287 aa | 298 aa | **+11** | CDK2 (C-terminal extension unresolved) |
| **1BUH** | B | 70 aa | 79 aa | **+9** | CksHs1 (N-terminal Met + disordered tail) |

**Worst case: 6A0Z** — The UniProt hemagglutinin sequence is 551 residues (full precursor including
signal peptide and transmembrane anchor), but only 270 residues are resolved in the crystal. Predicting
the full-length sequence would waste compute on 281 residues that cannot be evaluated and would distort
RMSD by including large disordered regions.

### Why Crystal-Derived Sequences

1. **Clean RMSD comparison**: Predictions cover exactly the resolved region of the crystal structure.
   Every predicted residue has a ground-truth coordinate for evaluation. No alignment ambiguity.

2. **Smaller input = faster predictions, less memory**: For 6A0Z, crystal-derived input is
   705 residues vs 989 UniProt residues. Boltz attention scales O(N^2), so this reduces memory
   by ~50%. Across 257 targets, crystal-derived sequences save significant GPU-hours.

3. **Standard practice in structural biology benchmarking**: CASP, CAMEO, and the original BM5.5
   benchmark all evaluate against the experimentally resolved region. Including unresolved
   residues would be methodologically incorrect.

4. **Consistent with BM5.5 benchmark design**: The bound-structure PDB files in BM5.5 contain
   only the crystallographically resolved chains. Our FASTAs now match these structures exactly.

### Chain Deduplication

For homo-multimers, only unique sequences are kept in prediction FASTAs:

- **119 targets** are homo-multimeric (have duplicate chain copies in the biological assembly)
- Example: A homodimer with chains A, B (identical) produces a single chain A in the FASTA
- This reduces Boltz attention memory from O(N^2) to O((N/k)^2) where k is the copy number
- Example: 3L89 has 24 chains / 3,924 residues but only 2 unique sequences / 327 residues
  - Without dedup: Boltz OOM on H100 80GB
  - With dedup: Completes in minutes on L40S 48GB
- All 11 original Boltz OOM failures were resolved by this deduplication

### Non-BM5.5 Chains Removed

7 targets had extra chains (peptides in MHC grooves, inhibitors, ternary complex partners) that
are not part of the BM5.5 docking pair. These were removed for consistency with the benchmark
definition, which specifies exactly two binding partners (receptor + ligand) per target.

### Chain Count Corrections

13 targets had chain count corrections where the original deduplication was too aggressive
(removed chains that appeared identical but were actually distinct binding partners with
slightly different conformations or were required for the docking pair definition).

### Uniformity Verification

All 257 targets verified: **AF FASTA == Boltz FASTA == Crystal PDB** (chain counts and
sequences match across all three inputs). Zero mismatches. This ensures that RMSD comparisons
are valid and that all predictors see exactly the same input.

### Implementation

Crystal-derived sequences were extracted from the ATOM records of BM5.5 bound-structure PDB
files using 3-letter to 1-letter amino acid conversion (including MSE->M, HSD/HSE/HSP->H).
The original UniProt-derived FASTAs from RCSB are preserved as `sequence.fasta.pre_blue_match`
backups in each target directory. All 257 targets have backups.

### Status

AF and Boltz are being **re-run with crystal-derived FASTAs**:
- AF: 257/257 complete with crystal-derived FASTAs
- Boltz: 149/257 complete, 108 re-running with deduplicated crystal-derived FASTAs (job 9304609)
- Rosetta relaxation will be re-run after Boltz completes

---

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

### Full BM5.5 Prediction (246 active targets) - ROSETTA RUNNING

| Step | Status | SLURM Job(s) | Notes |
|------|--------|-------------|-------|
| 0. Download BM5.5 | Done | - | 257 complexes (14 non-BM5.5 entries removed from archive) |
| 1. Clean PDBs | Done | 8824833 | 257/257 cleaned with Rosetta clean_pdb.py |
| 2. Download FASTAs | Done | - | 249 RCSB + 2 obsolete replacements + 4 PDB-extracted + 2 pre-existing |
| 3. Organize FASTAs | Done | - | 257 data/{ID}/sequence.fasta |
| 4. Prepare Boltz input | Done | - | 257 data/{ID}/boltz_input.fasta |
| 5. AlphaFold 2.3.2 | **Done (257/257)** | 8851183 + 8855266 + 8854324 + 9011401 + 9174798 + 9174799 | All complete. 7 AMBER failures resolved via FASTA fix |
| 6. Boltz-1 v0.4.1 | **149/257 done, 108 re-running** | 9304609 | 119 targets use dedup FASTAs (unique chains). All OOMs resolved |
| 7. Rosetta relaxation | **Running (partial)** | 9194317 (AI) + 9195061 (crystal) + 9304585 + 9304586 | Needs re-run after Boltz dedup completes for 108 targets |
| 8. AMBER relaxation | **Done (in Step 5)** | - | All 246 targets have 5 ranked (AMBER-relaxed) PDBs |
| 9. MolProbity validation | Waiting on Rosetta | - | Phenix + reduce |
| 10. Collect metrics | Waiting on Rosetta | - | PyMOL RMSD + Rosetta energies |

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

- [ ] MolProbity validation on full 257-target run
- [ ] PoseBusters validation
- [ ] Statistical analysis and figures
- [ ] Manuscript preparation

## Related Repositories

- [Protein_Relax_Pipeline](https://github.com/dreamlessx/Protein_Relax_Pipeline) - Contains the 20-protein test subset with all 6,820 structures
