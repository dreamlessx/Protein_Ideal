# Project Status

## Overview

Protein-Protein Complex Relaxation Benchmark using Docking Benchmark 5.5 (BM5.5).
Benchmarking AlphaFold 2.3.2 and Boltz-1 predictions against experimental crystal structures,
with Rosetta relaxation across 6 protocols.

**Lab**: Meiler Lab, Vanderbilt University
**Cluster**: ACCRE (csb_gpu_acc)
**Funding**: ARPA-H alphavirus vaccine development

## Dataset: PP Docking Benchmark 5.5

- **Total complexes in BM5.5**: ~257
- **Successfully predicted (AF + Boltz)**: 111 targets
  - `af_completed/`: 66 targets (fully done)
  - `afset/`: 45 targets (Boltz done, AF in progress)
- **Relaxation benchmark subset**: 20 proteins (in `test/`)

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

### Structure Prediction (111 targets)

**af_completed/ (66 targets)** - All fully done:
- 5 AlphaFold ranked PDBs per target
- 5 Boltz-1 prediction PDBs per target
- MSAs, ranking JSONs, timing files

**afset/ (45 targets)** - Boltz done, AlphaFold running (Job 8760262):
- Boltz-1: 100% complete (all 45 targets, 5 models each)
- AlphaFold: In progress on ACCRE

### 45 Remaining AF Targets

```
1AHW  1BGX  1DQJ  1E6J  1IQD  1IRA  1JWH  1K4C  1MLC
1NCA  1NSN  1WEJ  2BTF  2FD6  2HMI  2JEL  2OZA  2VIS
2VXT  2W9E  3EOA  3HI6  3L5W  3MXW  3SE8  3U7Y  3V6Z
3WD5  4CPA  4DN4  4DW2  4FP8  4FQI  4G6J  4G6M  4M5Z
5JMO  5WK3  5X0T  5Y9J  6A0Z  6A77  6AL0  6BPC  6OC3
```

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

## ACCRE Directory Layout

```
/data/p_csb_meiler/agarwm5/
├── af_completed/     # 66 targets, fully predicted (AF + Boltz)
├── afset/            # 45 targets, AF in progress
├── test/             # 20-protein relaxation benchmark (6,820 structures)
├── scripts/          # SLURM scripts, utilities
│   ├── af_dirlist.txt
│   ├── af_resume.slurm
│   ├── alphafold_array.slurm
│   ├── boltz_array.slurm
│   ├── relax_test.slurm
│   ├── relax_finish.slurm
│   ├── check_af_resume.sh
│   ├── check_boltz_progress.sh
│   └── check_relax_progress.sh
├── alphafold_analysis.csv
└── alphafold_complete_analysis.csv
```

## Software Versions

| Software | Version | Location on ACCRE |
|----------|---------|-------------------|
| AlphaFold | 2.3.2 | `/sb/apps/alphafold232/` |
| Boltz-1 | 0.4.1 | conda env |
| Rosetta | 3.15 | `/data/p_csb_meiler/apps/rosetta/rosetta-3.15/` |
| Python | 3.8.18 | AF2 conda env (af232) |
| CUDA | 12.6 | Driver 560.35.05 |

## Validation Pipeline (TODO)

- [ ] MolProbity validation on all 6,820 structures
- [ ] ProteinBusters validation
- [ ] Statistical analysis and figures
- [ ] Manuscript preparation

## Related Repositories

- [Protein_Relax_Pipeline](https://github.com/dreamlessx/Protein_Relax_Pipeline) - Contains the 20-protein test subset with all 6,820 structures
