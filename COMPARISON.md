# Comparison: Protein_Relax_Pipeline vs Protein_Ideal

Differences between the original pipeline ([Protein_Relax_Pipeline](https://github.com/dreamlessx/Protein_Relax_Pipeline))
and the current full BM5.5 run ([Protein_Ideal](https://github.com/dreamlessx/Protein_Ideal)).

## Dataset

| | Protein_Relax_Pipeline | Protein_Ideal |
|---|---|---|
| Dataset | BM5.5 subset | BM5.5 full |
| Total targets | 225 | 257 |
| Rigid-body | partial | 162 |
| Medium | partial | 60 |
| Difficult | partial | 35 |
| Non-standard IDs | unknown | BAAD, BOYV, BP57, CP57 (sequences extracted from ATOM records) |
| Obsolete PDBs | unknown | 1A2K (replaced by 5BXQ), 3RVW (replaced by 5VPG) |

**Note**: The Protein_Relax_Pipeline README states 225 complexes. The official BM5.5 benchmark
has 257. The 32-target discrepancy has not been investigated.

## AlphaFold 2.3.2 Configuration

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Memory | 6 GB | 64 GB |
| CPUs | 8 (`--cpus-per-task=8`) | 6 (`--ntasks=6`) |
| GPU | A6000 | A6000 |
| GPU relaxation | `--use_gpu_relax` (enabled) | `--nouse_gpu_relax` (disabled) |
| Relaxation | `--run_relax` (enabled) | not set |
| DB preset | `--db_preset=full_dbs` (explicit) | not set (full DBs specified individually) |
| Preset detection | Runs **both** monomer AND multimer for every target | Auto-detects monomer vs multimer from sequence count |
| Output structure | `af_out/monomer/` and `af_out/multimer/` (separate) | `af_out/sequence/` (single run) |
| Ranked models | 5 per preset (10 total: 5 mono + 5 multi) | 5 total |
| Completion check | Counts `ranked_*.pdb >= 5` per preset | Checks for `ranking_debug.json` existence |
| Environment vars | `TF_FORCE_UNIFIED_MEMORY=1`, `XLA_PYTHON_CLIENT_MEM_FRACTION=4.0` | not set |
| Singularity support | Yes (optional) | No |
| Data directory | `/sb/apps/alphafold-data.230` | `/csbtmp/alphafold-data.230` |
| Intermediate cleanup | Not in script | Deletes MSAs, pickles, intermediate PDBs post-run |
| Mail notifications | Enabled (`--mail-type=BEGIN,END,FAIL`) | Not set |
| FASTA location | `{target}/sequence/*.fasta` | `{target}/sequence.fasta` or `boltz_input.fasta` |

### Key Differences

1. **Monomer vs Multimer**: The Pipeline runs BOTH presets for every target and keeps both
   sets of predictions (10 ranked PDBs total). Protein_Ideal auto-detects based on chain
   count and runs only the appropriate preset (5 ranked PDBs).

2. **GPU Relaxation**: Pipeline uses AMBER GPU relaxation (`--use_gpu_relax --run_relax`).
   Protein_Ideal disables it (`--nouse_gpu_relax`). This means Pipeline's ranked PDBs
   are AMBER-relaxed while Protein_Ideal's are unrelaxed. This affects the starting
   structures for Rosetta relaxation.

3. **Memory**: Pipeline requests only 6 GB (relies on `XLA_PYTHON_CLIENT_MEM_FRACTION=4.0`
   for GPU memory overcommit via unified memory). Protein_Ideal requests 64 GB without
   unified memory settings. The Pipeline approach may be more memory-efficient for large
   complexes.

4. **Intermediate cleanup**: Protein_Ideal deletes MSAs, feature pickles, and intermediate
   PDBs after prediction to stay within a 30 GB disk quota. Pipeline does not clean up
   in the SLURM script.

## Boltz-1 v0.4.1 Configuration

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Memory | 256 GB | 256 GB |
| GPU | L40S | L40S |
| Diffusion samples | 5 | 5 |
| Recycling steps | 10 | 10 |
| Sampling steps | 200 | 200 |
| Output format | `--output_format pdb` (explicit) | not set (default) |
| Override flag | `--override` (enabled) | not set |
| FASTA validation | Validates `>CHAIN\|PROTEIN\|` headers with awk | Warning only (grep check) |
| Skip check | Counts PDBs in `predictions/*/boltz_model_*.pdb` | Counts `*.pdb` in `boltz_out_dir/` |
| Output directory | `./boltz_out_dir` | `./boltz_out_dir` |
| Data root | `/dors/meilerlab/home/agarwm5/benchmarking/data` | `/panfs/.../benchmarking/data/{ID}` |
| Target discovery | `find` in DATA_ROOT for FASTA files | DIRLIST_FILE (line-numbered) |

### Key Differences

1. **Output format**: Pipeline explicitly sets `--output_format pdb`. Protein_Ideal
   does not, relying on default behavior.

2. **Override**: Pipeline uses `--override` to force re-prediction. Protein_Ideal
   relies on the skip check instead.

3. **FASTA validation**: Pipeline validates headers strictly with awk and exits on
   bad headers. Protein_Ideal only warns.

## Rosetta Relaxation

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Rosetta version | 3.14 | 3.15 |
| Protocols | 6 (same names) | 6 (same names) |
| Replicates | 5 | 5 |
| Memory | 4 GB | TBD |
| Output format | `.pdb.gz` (`-out:pdb_gz`) | TBD |
| Common flags | `-ignore_zero_occupancy false`, `-flip_HNQ`, `-fa_max_dis 9.0`, `-optimization:default_max_cycles 200`, `-out:levels all:warning`, `-no_nstruct_label` | TBD |
| Suffix convention | `_r1` through `_r5` | TBD |
| Score file | `relax.fasc` per protocol dir | TBD |
| Input | Crystal PDB only (no AF/Boltz relaxation in this script) | TBD (will relax crystal, AF, and Boltz) |

### Key Differences

1. **Rosetta version**: Pipeline uses 3.14, Protein_Ideal uses 3.15. Score function
   behavior may differ slightly between versions.

2. **Relaxation scope**: The Pipeline script only relaxes the crystal structure PDB.
   AF/Boltz relaxation appears to be handled separately (not in the provided script).
   Protein_Ideal intends to relax all three sources in the same framework.

## Directory Structure

| | Protein_Relax_Pipeline | Protein_Ideal |
|---|---|---|
| Per-target layout | `data/{ID}/af_out/`, `data/{ID}/boltz_out/` | `data/{ID}/af_out/`, `data/{ID}/boltz_out_dir/` |
| Boltz output dir name | `boltz_out/` | `boltz_out_dir/` |
| AF monomer/multimer | Separate subdirectories | Single directory |
| FASTA location | `data/{ID}/boltz_input.fasta`, `data/{ID}/sequence.fasta` | Same |
| Relaxation output | `test_subset/{ID}/{protocol}/` | TBD |
| Test subset | `test_subset/` (20 proteins, 6,820 structures) | Not yet created |

## Scripts

| Script | Protein_Relax_Pipeline | Protein_Ideal |
|--------|----------------------|---------------|
| AF prediction | `scripts/prediction/alphafold_array.slurm` | `scripts/run/af_array.slurm` |
| Boltz prediction | `scripts/prediction/boltz_array.slurm` | `scripts/run/boltz_array.slurm` |
| Relaxation | `scripts/relaxation/relax_predictions.slurm` | TBD |
| PDB cleaning | `scripts/data_preparation/clean_pdbs.sh` | `scripts/run/clean_array.slurm` |
| FASTA download | `scripts/data_preparation/download_fastas.py` | Same (with Python 3.9 fix) |
| FASTA organize | `scripts/data_preparation/organize_fastas.py` | N/A (done inline) |
| Boltz FASTA prep | `scripts/data_preparation/prepare_boltz_fastas.py` | N/A (done inline) |
| Metrics collection | `scripts/analysis/collect_metrics.py` | TBD |
| MolProbity | `scripts/validation/run_molprobity.sh` | TBD |

## FASTA Handling

| | Protein_Relax_Pipeline | Protein_Ideal |
|---|---|---|
| Source | RCSB download | RCSB download + manual fixes |
| Obsolete PDB handling | Unknown | Documented: 1A2K->5BXQ, 3RVW->5VPG |
| Non-standard IDs | Unknown | BAAD, BOYV, BP57, CP57 extracted from ATOM records |
| Python compatibility | Requires Python 3.10+ (`str \| None`) | Fixed for Python 3.9 (`from __future__ import annotations`) |

## Summary of Impact

The most significant methodological differences that could affect results:

1. **AF relaxation state**: Pipeline produces AMBER-relaxed ranked PDBs; Protein_Ideal
   produces unrelaxed ranked PDBs. Rosetta relaxation starting from different baselines.
2. **AF mono+multi vs auto-detect**: Pipeline keeps both monomer and multimer predictions
   (10 models). Protein_Ideal keeps only the appropriate preset (5 models).
3. **Rosetta version**: 3.14 vs 3.15 may produce slightly different energy landscapes.
4. **TF unified memory**: Pipeline uses GPU memory overcommit which allows running with
   only 6 GB system RAM. Protein_Ideal allocates 64 GB system RAM without overcommit.
5. **Dataset size**: 225 vs 257 targets.
