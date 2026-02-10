# Comparison: Protein_Relax_Pipeline vs Protein_Ideal

Differences between the original pipeline ([Protein_Relax_Pipeline](https://github.com/dreamlessx/Protein_Relax_Pipeline))
and the current full BM5.5 run ([Protein_Ideal](https://github.com/dreamlessx/Protein_Ideal)).

All values verified against actual SLURM scripts and READMEs in both repositories.

## Dataset

| | Protein_Relax_Pipeline | Protein_Ideal |
|---|---|---|
| Dataset | BM5.5 full | BM5.5 full |
| Total targets | 257 | 257 |
| Rigid-body | 162 | 162 |
| Medium | 60 | 60 |
| Difficult | 35 | 35 |
| Non-standard IDs | BAAD, BOYV, BP57, CP57 | BAAD, BOYV, BP57, CP57 (sequences extracted from ATOM records) |
| Obsolete PDBs | Unknown | 1A2K (replaced by 5BXQ), 3RVW (replaced by 5VPG) |

Both pipelines now target the full BM5.5 benchmark (257 complexes). Pipeline originally had
15 extra non-BM5.5 entries from the benchmark5.5.tgz archive which were removed.

## AlphaFold 2.3.2 Configuration

### SLURM Resources

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Memory | 6 GB (script) / 60 GB (README) | 64 GB (128 GB highmem variant) |
| CPUs | 8 (`--cpus-per-task=8`) | 6 (`--ntasks=6`) |
| GPU | A6000 | A6000 |
| Wall time | 48 h | 48 h |
| Account | `csb_gpu_acc` | `csb_gpu_acc` |
| Mail notifications | `BEGIN,END,FAIL` to `mudit.agarwal@vanderbilt.edu` | Not set |
| Separate stderr | Yes (separate .out and .err) | Yes (separate .out and .err) |

### AlphaFold Flags

| Flag | Protein_Relax_Pipeline | Protein_Ideal |
|------|----------------------|---------------|
| `--use_gpu_relax` / `--nouse_gpu_relax` | `--use_gpu_relax` (GPU) | `--nouse_gpu_relax` (CPU) |
| `--run_relax` | `--run_relax` (explicit) | not set (defaults to True) |
| `--models_to_relax` | `all` | `all` |
| `--db_preset` | `full_dbs` primary, `reduced_dbs` fallback on HHblits failure | `full_dbs` primary, `reduced_dbs` fallback on HHblits failure |
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
| Output structure | `af_out/monomer/`, `af_out/multimer/`, `af_out_unrelaxed/`, `af_out_relaxed/` | `af_out/sequence/` (single dir, both relaxed + unrelaxed) |
| Total AF models per target | 10 per preset (5 relaxed + 5 unrelaxed); 20 total (mono + multi) | 10 (5 relaxed + 5 unrelaxed) |
| Unrelaxed models kept | Yes (saved to `af_out_unrelaxed/`) | Yes (kept in `af_out/sequence/`) |
| Relaxed models | All 5 per preset (GPU relax, saved to `af_out_relaxed/`) | All 5 (CPU relax, saved as `ranked_*.pdb`) |
| AMBER relaxation treatment | 7th relaxation protocol (alongside 6 Rosetta protocols) | 7th relaxation protocol (alongside 6 Rosetta protocols) |
| Completion check | Counts `ranked_*.pdb >= 5` per preset dir | Checks for `ranking_debug.json` glob |
| FASTA discovery | Globs `*.fa,*.fasta,*.faa,*.fas,*.fna` in `sequence/` | Checks `sequence.fasta` then `boltz_input.fasta` |
| Target discovery | `find` + `sort` on `afset/` subdirectories | Line-numbered `af_dirlist.txt` |
| Intermediate cleanup | Deletes MSAs, pickles, timings | Deletes MSAs, pickles, relaxed duplicates, timings post-run |
| Singularity support | Yes (optional, via `AF_SIF` variable) | No |
| Data directory | `/sb/apps/alphafold-data.230` | `/csbtmp/alphafold-data.230` |

### Key Differences

1. **Monomer vs Multimer**: Pipeline runs BOTH presets for every target and keeps both
   sets of predictions (up to 20 AF models total: 10 monomer + 10 multimer, each with
   relaxed and unrelaxed). Protein_Ideal auto-detects based on chain count and runs only
   the appropriate preset (10 models: 5 relaxed + 5 unrelaxed).

2. **AMBER Relaxation**: Both pipelines run AMBER relaxation (OpenMM, ff14SB) on all 5 models
   and save both unrelaxed and relaxed versions. Pipeline uses GPU (`--use_gpu_relax`).
   Protein_Ideal uses CPU (`--nouse_gpu_relax`). Both treat AMBER relaxation as one of 7
   relaxation protocols.

3. **Memory strategy**: Pipeline requests 6 GB system RAM in the SLURM script and relies on
   `TF_FORCE_UNIFIED_MEMORY=1` + `XLA_PYTHON_CLIENT_MEM_FRACTION=4.0` for GPU memory
   overcommit via unified memory. Pipeline README documents 60 GB. Protein_Ideal requests
   64 GB system RAM (128 GB for large complexes) without unified memory settings.

4. **Intermediate cleanup**: Both pipelines clean up intermediates (MSAs, pickles, timings)
   after prediction. Pipeline additionally organizes outputs into separate `af_out_unrelaxed/`
   and `af_out_relaxed/` directories. Protein_Ideal keeps all outputs in a single
   `af_out/sequence/` directory.

## AMBER Relaxation (OpenMM)

Both pipelines use AlphaFold's native AMBER relaxation via OpenMM as the 7th relaxation
protocol alongside 6 Rosetta protocols.

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Force field | AMBER ff14SB | AMBER ff14SB (AF default) |
| Energy tolerance | 2.39 kcal/mol | AF default (2.39 kcal/mol) |
| Position restraint stiffness | 10.0 kcal/mol/A^2 | AF default (10.0 kcal/mol/A^2) |
| Compute | GPU (`--use_gpu_relax`) | CPU (`--nouse_gpu_relax`) |
| Models relaxed | All 5 (`--models_to_relax=all`) | All 5 (`--models_to_relax=all`) |
| Unrelaxed models saved | Yes (`af_out_unrelaxed/`) | Yes (`unrelaxed_model_*.pdb`) |

AMBER relaxation parameters are identical (both use AF 2.3.2 defaults). The only difference
is GPU vs CPU execution, which produces numerically equivalent results.

## Boltz-1 v0.4.1 Configuration

### SLURM Resources

| Parameter | Protein_Relax_Pipeline | Protein_Ideal |
|-----------|----------------------|---------------|
| Memory | 256 GB | 256 GB |
| CPUs | 1 | 1 |
| GPU | L40S | L40S (standard), H100 80GB (highmem) |
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
| `--output_format` | `pdb` (explicit) | `pdb` (explicit, added after CIF bug fix) |
| `--override` | Yes | not set |
| `--out_dir` | `./boltz_out_dir` | `./boltz_out_dir` |
| `--cache` | `$HOME/.boltz` | `$HOME/.boltz` |

### Execution Logic

| Behavior | Protein_Relax_Pipeline | Protein_Ideal |
|----------|----------------------|---------------|
| Output type | Unrelaxed (native Boltz predictions) | Unrelaxed (native Boltz predictions) |
| FASTA validation | Strict: `awk` checks every header matches `>X\|PROTEIN\|`; exits on failure | Warning only: `grep` check, continues on mismatch |
| FASTA preference | `boltz_input.fasta` > `sequence.fasta` | `boltz_input.fasta` > `sequence.fasta` |
| Skip check | Counts `boltz_model_*.pdb` in predictions subdir | Counts `*.pdb` in `boltz_out_dir/` |
| Force rerun | `FORCE=1` env var | `FORCE=1` env var |
| Target discovery | `find` at depth 2 under `DATA_ROOT` | Line-numbered `af_dirlist.txt` |
| Data root | `/dors/meilerlab/home/agarwm5/benchmarking/data` | `/panfs/.../benchmarking/data/{ID}` |
| Debug output | `set -x` around predict command | None |

### Key Differences

1. **Output format**: Both pipelines explicitly set `--output_format pdb`. Protein_Ideal
   added this after initial run produced CIF files instead of PDB (Boltz default is CIF).

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
| Input | Crystal PDB only (script) | TBD (crystal + AF + Boltz) |
| Output format | `.pdb.gz` (compressed) | TBD |
| Score file | `relax.fasc` per protocol dir | TBD |
| Target discovery | Regex `[0-9A-Za-z]{4}` dirs under `$ROOT` | TBD |
| PDB selection | `$code.pdb` > first `*.pdb` sorted | TBD |

### Key Differences

1. **Rosetta version**: Pipeline uses 3.14, Protein_Ideal uses 3.15. Score function
   behavior may differ slightly between versions.

2. **Relaxation scope**: Pipeline script (`relax_predictions.slurm`) only relaxes
   crystal structure PDBs. Pipeline README documents relaxing all three sources
   (crystal, AF, Boltz). Protein_Ideal intends to relax all three sources in a
   unified framework.

## Relaxation Protocol Summary

Both pipelines define 7 relaxation protocols:

| # | Protocol | Method | Protein_Relax_Pipeline | Protein_Ideal |
|---|----------|--------|----------------------|---------------|
| 1 | AMBER (native) | AlphaFold OpenMM (ff14SB) | GPU relax during AF prediction | CPU relax during AF prediction |
| 2 | cart_beta | Rosetta cartesian, beta_nov16 | 5 replicates | 5 replicates (planned) |
| 3 | cart_ref15 | Rosetta cartesian, ref2015 | 5 replicates | 5 replicates (planned) |
| 4 | dual_beta | Rosetta dualspace, beta_nov16 | 5 replicates | 5 replicates (planned) |
| 5 | dual_ref15 | Rosetta dualspace, ref2015 | 5 replicates | 5 replicates (planned) |
| 6 | norm_beta | Rosetta normal, beta_nov16 | 5 replicates | 5 replicates (planned) |
| 7 | norm_ref15 | Rosetta normal, ref2015 | 5 replicates | 5 replicates (planned) |

Applied to: crystal structures, AF unrelaxed predictions, and Boltz predictions.

## Directory Structure

| | Protein_Relax_Pipeline | Protein_Ideal |
|---|---|---|
| Per-target layout | `data/{ID}/af_out/`, `data/{ID}/af_out_unrelaxed/`, `data/{ID}/af_out_relaxed/`, `data/{ID}/boltz_out/` | `data/{ID}/af_out/`, `data/{ID}/boltz_out_dir/` |
| AF relaxed output | `af_out_relaxed/ranked_*.pdb` | `af_out/sequence/ranked_*.pdb` |
| AF unrelaxed output | `af_out_unrelaxed/unrelaxed_model_*.pdb` | `af_out/sequence/unrelaxed_model_*.pdb` |
| AF monomer/multimer | Separate subdirectories (`monomer/`, `multimer/`) in `af_out/` | Single directory (`sequence/`) in `af_out/` |
| Boltz output dir name | `boltz_out/` | `boltz_out_dir/` |
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
| Non-standard IDs | BAAD, BOYV, BP57, CP57 documented | BAAD, BOYV, BP57, CP57 extracted from ATOM records |
| Python compatibility | Requires Python 3.10+ (`str | None`) | Fixed for Python 3.9 (`from __future__ import annotations`) |

## Summary of Impact

The most significant methodological differences that could affect results:

1. **Monomer vs Multimer**: Pipeline runs BOTH presets for every target (up to 20 AF
   models). Protein_Ideal auto-detects and runs only the appropriate preset (10 models).
   This is the largest structural difference between the two approaches.

2. **AMBER relaxation compute**: Both pipelines AMBER-relax all 5 models via OpenMM
   (ff14SB). Pipeline uses GPU relax; Protein_Ideal uses CPU relax. Both save unrelaxed
   models as baselines. GPU vs CPU relax produces numerically equivalent results.

3. **Memory strategy**: Pipeline requests 6 GB system RAM in scripts and relies on
   TensorFlow unified memory overcommit (GPU overcommit). Protein_Ideal allocates
   64-128 GB system RAM without unified memory settings.

4. **Rosetta version**: 3.14 vs 3.15 may produce slightly different energy landscapes
   and score function behavior.

5. **AF output organization**: Pipeline separates relaxed and unrelaxed into distinct
   directories (`af_out_relaxed/`, `af_out_unrelaxed/`). Protein_Ideal keeps both in
   a single `af_out/sequence/` directory.

6. **Database preset**: Both pipelines use `full_dbs` as primary with `reduced_dbs` fallback
   on HHblits failure. Confirmed HHblits failures on antibody/immunoglobulin targets that hit
   titin-like sequences in BFD (32763 residue limit). Pipeline: built-in from start.
   Protein_Ideal: added after 1IRA failure.

7. **HHblits fallback mechanism**: Both pipelines wrap the AF call in a retry function.
   On failure, the script checks for existing `unrelaxed_model_*.pdb` files. If present,
   AMBER failed but prediction succeeded — unrelaxed models are preserved. If absent,
   HHblits failed — output is cleaned and AF retries with `--db_preset=reduced_dbs` +
   `--small_bfd_database_path`. Three targets confirmed: 1IRA, 1DQJ, 1MLC all completed
   with reduced_dbs fallback. Full_dbs uses HHblits + BFD + UniRef30; reduced_dbs uses
   jackhmmer + small_bfd.

8. **AMBER crash recovery**: Both pipelines run AMBER on all 5 models
   (`--models_to_relax=all`). If AMBER crashes (e.g., 1ATN: `ValueError: residue with
   no atoms`), unrelaxed models survive as baseline for Rosetta relaxation. The script
   detects partial output (unrelaxed models present, no ranking_debug.json) and preserves
   them rather than deleting everything during a reduced_dbs retry.

9. **Boltz GPU tiering**: Pipeline uses single L40S tier. Protein_Ideal stratifies by
   residue count:

   | Tier | GPU | Samples | Residue Range | Targets | Result |
   |------|-----|---------|---------------|---------|--------|
   | Standard | L40S 48GB | 5 | <1300 | 234 | 234/234 |
   | Highmem | H100 80GB | 5 | 1300-2200 | 14 | 12/14 |
   | XL | H100 80GB | 1 | >2200 | 11 | 2/11 |

   Final: 248/257 (96.5%). 9 targets >3000 residues permanently OOMed (AF-only):
   1DE4, 1K5D, 1N2C, 1WDW, 1ZM4, 3BIW, 3L89, 4GXU, 6EY6.

10. **DNA/RNA exclusion**: Both pipelines exclude DNA/RNA chains from prediction FASTAs.
    BM5.5 is a protein-protein benchmark; neither AF nor Boltz supports nucleic acids.
    Protein_Ideal audited all 257 targets and removed DNA from 3P57 (2 DNA strands) and
    1H9D (2 DNA strands). BP57/CP57 already protein-only.

11. **Input verification**: Protein_Ideal FASTAs verified against dreamlessx's
    authoritative set (265 files in Protein_Relax_Pipeline `fasta/`). Of 251 overlapping
    targets: 48 byte-identical, 203 same sequences with different chain order, 0 truly
    different. Chain order difference: Protein_Ideal uses BM5.5 receptor-first order;
    Pipeline uses RCSB chain-ID order. Both are valid; difference is cosmetic.

12. **Chain ordering effect on AF-Multimer**: AF-Multimer processes chains in FASTA
    order. The reversed chain ordering between pipelines (203/251 targets) may produce
    slightly different MSA pairing and template matching. For relaxation analysis, this is
    irrelevant (MolProbity, clashscore, Ramachandran are chain-order-independent). For
    DockQ comparison, proper alignment handles this. If both pipelines produce consistent
    relaxation results despite different chain order, this demonstrates robustness.
