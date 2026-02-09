# Comparison: Protein_Relax_Pipeline vs Protein_Ideal

Differences between the original pipeline ([Protein_Relax_Pipeline](https://github.com/dreamlessx/Protein_Relax_Pipeline))
and the current full BM5.5 run ([Protein_Ideal](https://github.com/dreamlessx/Protein_Ideal)).

All values verified against actual SLURM scripts in both repositories.

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

### SLURM Resources

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Memory | 6 GB | 64 GB (128 GB highmem variant) |
| CPUs | 8 (`--cpus-per-task=8`) | 6 (`--ntasks=6`) |
| GPU | A6000 | A6000 |
| Wall time | 48 h | 48 h |
| Account | `csb_gpu_acc` | `csb_gpu_acc` |
| Mail notifications | `BEGIN,END,FAIL` to `mudit.agarwal@vanderbilt.edu` | Not set |
| Separate stderr | No (combined in .out) | Yes (separate .out and .err) |

### AlphaFold Flags

| Flag | Protein_Relax_Pipeline | Protein_Ideal |
|------|----------------------|---------------|
| `--use_gpu_relax` / `--nouse_gpu_relax` | `--use_gpu_relax` (GPU) | `--nouse_gpu_relax` (CPU) |
| `--run_relax` | `--run_relax` (explicit) | not set (defaults to True) |
| `--models_to_relax` | not set (defaults to `best`) | `--models_to_relax=all` |
| `--db_preset` | `--db_preset=full_dbs` (explicit) | not set (databases specified individually) |
| `--max_template_date` | `9999-12-31` | `9999-12-31` |
| `--model_preset` | Both `monomer` and `multimer` per target | Auto-detected from sequence count |
| `--num_multimer_predictions_per_model` | `1` (multimer only) | `1` (multimer only) |

### Environment Variables

| Variable | Protein_Relax_Pipeline | Protein_Ideal |
|----------|----------------------|---------------|
| `TF_FORCE_UNIFIED_MEMORY` | `1` | not set |
| `XLA_PYTHON_CLIENT_MEM_FRACTION` | `4.0` | not set |
| `OMP_NUM_THREADS` | `${SLURM_CPUS_PER_TASK:-8}` | not set |

### Execution Logic

| Behavior | Protein_Relax_Pipeline | Protein_Ideal |
|----------|----------------------|---------------|
| Preset execution | Runs **both** monomer AND multimer for every target | Auto-detects: >1 sequence = multimer, else monomer |
| Output structure | `af_out/monomer/` and `af_out/multimer/` (separate dirs) | `af_out/sequence/` (single dir) |
| Total ranked models | 10 per target (5 mono + 5 multi) | 5 per target |
| Relaxed models | 1 per preset (best only, GPU relax) | All 5 (CPU relax) |
| Completion check | Counts `ranked_*.pdb >= 5` per preset dir | Checks for `ranking_debug.json` glob |
| FASTA discovery | Globs `*.fa,*.fasta,*.faa,*.fas,*.fna` in `sequence/` | Checks `sequence.fasta` then `boltz_input.fasta` |
| Target discovery | `find` + `sort` on `afset/` subdirectories | Line-numbered `af_dirlist.txt` |
| Intermediate cleanup | None | Deletes MSAs, pickles, intermediate PDBs post-run |
| Singularity support | Yes (optional, via `AF_SIF` variable) | No |
| Data directory | `/sb/apps/alphafold-data.230` | `/csbtmp/alphafold-data.230` |

### Key Differences

1. **Monomer vs Multimer**: Pipeline runs BOTH presets for every target and keeps both
   sets of predictions (10 ranked PDBs total). Protein_Ideal auto-detects based on chain
   count and runs only the appropriate preset (5 ranked PDBs).

2. **AMBER Relaxation**: Both pipelines run AMBER relaxation. Pipeline uses GPU
   (`--use_gpu_relax`) on the best model only (default `--models_to_relax=best`).
   Protein_Ideal uses CPU (`--nouse_gpu_relax`) on all 5 models (`--models_to_relax=all`).
   Both produce AMBER-relaxed ranked PDBs.

3. **Memory strategy**: Pipeline requests only 6 GB system RAM and relies on
   `TF_FORCE_UNIFIED_MEMORY=1` + `XLA_PYTHON_CLIENT_MEM_FRACTION=4.0` for GPU memory
   overcommit via unified memory. Protein_Ideal requests 64 GB system RAM (128 GB for
   large complexes) without unified memory settings.

4. **Intermediate cleanup**: Protein_Ideal deletes MSAs, feature pickles, and intermediate
   PDBs after prediction to stay within a 30 GB disk quota. Pipeline retains all
   intermediate files.

## Boltz-1 v0.4.1 Configuration

### SLURM Resources

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Memory | 256 GB | 256 GB |
| CPUs | 1 | 1 |
| GPU | L40S | L40S |
| Wall time | 2 days | 2 days |
| Account | `p_meiler_acc` | `p_meiler_acc` |
| Mail notifications | `BEGIN,END,FAIL` (no recipient set) | Not set |
| Separate stderr | No (combined in .out) | Yes (separate .out and .err) |

### Boltz Flags

| Flag | Protein_Relax_Pipeline | Protein_Ideal |
|------|----------------------|---------------|
| `--use_msa_server` | Yes | Yes |
| `--diffusion_samples` | 5 | 5 |
| `--recycling_steps` | 10 | 10 |
| `--sampling_steps` | 200 | 200 |
| `--output_format` | `pdb` (explicit) | not set (default) |
| `--override` | Yes | not set |
| `--out_dir` | `./boltz_out_dir` | `./boltz_out_dir` |
| `--cache` | `$HOME/.boltz` | `$HOME/.boltz` |

### Execution Logic

| Behavior | Protein_Relax_Pipeline | Protein_Ideal |
|----------|----------------------|---------------|
| FASTA validation | Strict: `awk` checks every header matches `>X\|PROTEIN\|`; exits on failure | Warning only: `grep` check, continues on mismatch |
| FASTA preference | `boltz_input.fasta` > `sequence.fasta` | `boltz_input.fasta` > `sequence.fasta` |
| Skip check | Counts `boltz_model_*.pdb` in predictions subdir | Counts `*.pdb` in `boltz_out_dir/` |
| Force rerun | `FORCE=1` env var | `FORCE=1` env var |
| Target discovery | `find` at depth 2 under `DATA_ROOT` | Line-numbered `af_dirlist.txt` |
| Data root | `/dors/meilerlab/home/agarwm5/benchmarking/data` | `/panfs/.../benchmarking/data/{ID}` |
| Debug output | `set -x` around predict command | None |

### Key Differences

1. **Output format**: Pipeline explicitly sets `--output_format pdb`. Protein_Ideal
   does not, relying on default behavior.

2. **Override**: Pipeline uses `--override` to force re-prediction. Protein_Ideal
   relies on the skip check instead.

3. **FASTA validation**: Pipeline validates headers strictly with awk and exits on
   bad headers (exit code 3). Protein_Ideal only warns and continues.

## Rosetta Relaxation

### SLURM Resources

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Rosetta version | 3.14 | 3.15 |
| Memory | 4 GB | TBD |
| CPUs | 1 | TBD |
| GPU | None (CPU only) | TBD |
| Wall time | 48 h | TBD |
| Account | `p_csb_meiler` | TBD |
| Partition | `batch` (CPU) | TBD |

### Protocols (identical names, 6 total)

| Protocol | Flags |
|----------|-------|
| `cart_beta` | `-relax:cartesian -beta_nov16 -score:weights beta_nov16_cart` |
| `cart_ref15` | `-relax:cartesian -score:weights ref2015_cart` |
| `dual_beta` | `-relax:dualspace -beta_nov16 -score:weights beta_nov16_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| `dual_ref15` | `-relax:dualspace -score:weights ref2015_cart -nonideal -relax:minimize_bond_angles -relax:minimize_bond_lengths` |
| `norm_beta` | `-beta_nov16 -score:weights beta_nov16` |
| `norm_ref15` | `-score:weights ref2015` |

### Common Rosetta Flags (Pipeline, verified)

```
-ignore_zero_occupancy false
-nstruct 1
-no_nstruct_label
-out:pdb_gz
-flip_HNQ
-fa_max_dis 9.0
-optimization:default_max_cycles 200
-out:levels all:warning
-out::suffix "_r${r}"
-scorefile relax.fasc
```

### Execution Logic

| Behavior | Protein_Relax_Pipeline | Protein_Ideal |
|----------|----------------------|---------------|
| Replicates | 5 (`_r1` through `_r5`) | 5 (planned) |
| Skip guard | None (always runs all 30) | TBD |
| Input | Crystal PDB only | TBD (crystal + AF + Boltz) |
| Output format | `.pdb.gz` (compressed) | TBD |
| Score file | `relax.fasc` per protocol dir | TBD |
| Target discovery | Regex `[0-9A-Za-z]{4}` dirs under `$ROOT` | TBD |
| PDB selection | `$code.pdb` > first `*.pdb` sorted | TBD |

### Key Differences

1. **Rosetta version**: Pipeline uses 3.14, Protein_Ideal uses 3.15. Score function
   behavior may differ slightly between versions.

2. **Relaxation scope**: Pipeline script only relaxes the crystal structure PDB.
   AF/Boltz relaxation appears to be handled separately (not in the provided script).
   Protein_Ideal intends to relax all three sources (crystal, AF, Boltz) in a unified framework.

## Directory Structure

| | Protein_Relax_Pipeline | Protein_Ideal |
|---|---|---|
| Per-target layout | `data/{ID}/af_out/`, `data/{ID}/boltz_out/` | `data/{ID}/af_out/`, `data/{ID}/boltz_out_dir/` |
| Boltz output dir name | `boltz_out/` | `boltz_out_dir/` |
| AF monomer/multimer | Separate subdirectories (`monomer/`, `multimer/`) | Single directory (`sequence/`) |
| FASTA location | `data/{ID}/sequence/*.fasta` (globbed) | `data/{ID}/sequence.fasta` or `boltz_input.fasta` |
| Relaxation output | `test_subset/{ID}/{protocol}/` | TBD |
| Cleaned PDBs | Unknown | `cleaned/{ID}.pdb` (via Rosetta `clean_pdb.py` array job) |

## Scripts

| Script | Protein_Relax_Pipeline | Protein_Ideal |
|--------|----------------------|---------------|
| AF prediction | `scripts/prediction/alphafold_array.slurm` | `scripts/run/af_array.slurm` |
| AF highmem | N/A | `scripts/run/af_array_highmem.slurm` (128 GB) |
| Boltz prediction | `scripts/prediction/boltz_array.slurm` | `scripts/run/boltz_array.slurm` |
| Relaxation | `scripts/relaxation/relax_predictions.slurm` | TBD |
| PDB cleaning | `scripts/data_preparation/clean_pdbs.sh` (serial) | `scripts/run/clean_array.slurm` (array) |
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
| Python compatibility | Requires Python 3.10+ (`str | None`) | Fixed for Python 3.9 (`from __future__ import annotations`) |

## Summary of Impact

The most significant methodological differences that could affect results:

1. **AF model count**: Pipeline produces 10 ranked PDBs per target (5 monomer + 5 multimer).
   Protein_Ideal produces 5 (auto-detected preset only). Pipeline provides both binding
   conformations for comparison; Protein_Ideal uses only the structurally appropriate preset.

2. **AMBER relaxation scope**: Pipeline AMBER-relaxes only the best-ranked model per preset
   (GPU). Protein_Ideal AMBER-relaxes all 5 models (CPU). This means all 5 ranked PDBs from
   Protein_Ideal are relaxed, while only ranked_0 from each Pipeline preset is relaxed.

3. **Memory strategy**: Pipeline relies on TensorFlow unified memory overcommit (6 GB system +
   GPU overcommit). Protein_Ideal allocates 64-128 GB system RAM. The Pipeline approach can
   handle larger complexes with less system RAM but is less predictable for OOM behavior.

4. **Rosetta version**: 3.14 vs 3.15 may produce slightly different energy landscapes and
   score function behavior.

5. **Dataset size**: 225 vs 257 targets (32 target discrepancy uninvestigated).
