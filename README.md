# Protein_Ideal: Green Pipeline (matched-parameters re-run of BM5.5 docking-relaxation)

Independent verification of the Blue pipeline at [`Protein_Relax_Pipeline`](https://github.com/dreamlessx/Protein_Relax_Pipeline). Green re-runs Blue's full pipeline from scratch with matched parameters: same 257 BM5.5 targets, same 27 input structures per target, same AMBER force field and AlphaFold/Boltz versions, same six Rosetta protocols with identical flags, same five replicates per protocol. The locked DB unifies Blue + Green under snapshot 2026-04-27a.

> **Where to look for canonical analysis.** Figures, tables, statistical analyses, and the three paper findings live in `Protein_Relax_Pipeline/red_analysis/`. This repo contains Green's pipeline scripts and Green-specific output (`green_data_analysis/`).

---

## What Blue + Green together accomplish

Two independent pipelines run from the same FASTAs through the same prediction methods (AlphaFold 2.3.2, Boltz-1 v0.4.1) and the same relaxation matrix (1 AMBER + 6 Rosetta protocols × 5 reps × 27 input structures × 257 targets), producing 208,170 cells per pipeline. The DB unifies them as 416,340 `rosetta_metrics` rows under snapshot 2026-04-27a, with `pipeline_id ∈ {blue, green}` distinguishing source.

**Blue/Green agreement** (locked snapshot):

| Metric | Pearson r | n |
|---|---|---|
| Pre-Rosetta TM | 0.997 | 1,128 |
| Pre-Rosetta RMSD | 0.994 | 1,128 |
| Post-Rosetta TM | 0.999 | 60 |
| Per-source clashscore | 0.867 to 0.991 | 257 |
| Per-source MP score | 0.941 to 0.984 | 257 |

The Green run statistically reproduces Blue. All three paper findings (AMBER fixes local geometry, crystal worst MolProbity, dualspace_beta wins integrated MP) replicate independently.

## Five findings (full numbers in `Protein_Relax_Pipeline/red_analysis/PAPER_FINDINGS.md`)

1. **AMBER fixes local geometry without touching global fold.** Clashscore Cliff's d = -0.99 at TM Cliff's d = -0.01. AMBER improves MolProbity for 257/257 AlphaFold and 256/257 Boltz targets.
2. **Crystal structures carry the worst pre-Rosetta MolProbity.** Crystal clashscore 13.85 vs AlphaFold-relaxed 2.82 vs AMBER(Boltz) 1.60. Idealization artifact, not failure.
3. **dualspace_beta wins integrated MolProbity at small TM cost.** beta_nov16 dominates ref2015 on MP/clash/Rama-favored across 40-42 of 42 (pipeline, source, move-set) triples.

## DB state under snapshot 2026-04-27a (qc_status = pass)

| Table | Rows |
|---|---|
| `rosetta_metrics` | 416,340 |
| `prerosetta_metrics` | 13,364 |
| `tm_scores` | 105,550 (12,850 pre + 92,700 post) |
| `rosetta_energy` | 416,340 (100% coverage) |
| `targets` | 257 with full metadata + parent_pdb_id for 4 non-standard |
| `qc_quarantine` | 0 |

DB and raw TSVs in the [`db-2026-04-27a-supp`](https://github.com/dreamlessx/Protein_Relax_Pipeline/releases/tag/db-2026-04-27a-supp) Release on the primary repo.

---

## Differences between Blue and Green

Both pipelines use identical Rosetta flags, identical AMBER parameters, the same FASTAs, and the same prediction methods. Differences are operational, not scientific.

| Aspect | Blue | Green |
|---|---|---|
| ACCRE root | `/data/p_csb_meiler/agarwm5/protein_pipeline/` | `/data/p_csb_meiler/agarwm5/protein_ideal_test/` |
| Job prefix | `blue_` | `green_` |
| Rosetta version | 3.15 | 3.15 |
| Script architecture | Single-stage SLURM arrays | Modular per-step scripts in `scripts/run/`, `scripts/relaxation/`, `scripts/validation/`, `scripts/analysis/`, `scripts/data_preparation/` |
| AMBER (crystal) compute | GPU OpenMM | GPU OpenMM (matched) |
| Per-target output count | 810 Rosetta runs | 810 Rosetta runs (matched) |

Full Blue/Green diff in `COMPARISON.md`.

---

## Dataset

| Quantity | Value |
|---|---|
| BM5.5 targets | 257 |
| Rigid-body / Medium / Difficult | 162 / 60 / 35 |
| Total chains | 605 |
| Total residues | 122,966 |
| Non-standard zlab IDs | 4 (BAAD, BOYV, BP57, CP57; parent_pdb_id populated in DB) |

FASTAs are derived from crystal coordinates, not RCSB canonical sequences. Of 257 targets, 241 differ from RCSB. Crystal stripping removed homo-multimer duplicate chains in 36 PDBs. His-tags removed from 41 targets. DNA/RNA chains excluded.

## Repository layout

```
Protein_Ideal/
├── data/                 Per-target inputs (cleaned crystals, FASTAs, prediction outputs)
├── cleaned/              257 cleaned crystal PDBs
├── merged/               Pre-cleaning input PDBs
├── scripts/
│   ├── data_preparation/   Crystal cleanup, FASTA derivation, Boltz-1 input prep
│   ├── run/                AlphaFold + Boltz batch runners
│   ├── relaxation/         Standalone AMBER, Rosetta protocol runners
│   ├── validation/         MolProbity, TM-score, energy extraction
│   └── analysis/           Per-pipeline aggregation
├── green_data_analysis/  Green-specific bar + scatter figures (per metric)
├── PROJECT_STATUS.md     Current state at lock
├── NOTEBOOK.md           Lab notebook chronology (2026-02-07 → 2026-04-27 lock)
├── COMPARISON.md         Blue/Green protocol diff
└── README.md             This file
```

`green_data_analysis/` mirrors metric-specific bar and scatter figures (clashscore, MP score, Rama outliers, Rama favored, rotamer outliers, C-beta outliers, RMS bonds, RMS angles, energy) for the Green pipeline. Combined Blue + Green figures live in `Protein_Relax_Pipeline/red_analysis/figures/` with `_blue` and `_green` variants where pipeline matters.

## Quickstart (Green re-run from scratch)

For end-users querying the locked DB, use the primary repo's release artifact directly. This section is for re-running Green on ACCRE.

```bash
git clone git@github.com:dreamlessx/Protein_Ideal.git
cd Protein_Ideal

# 1. Crystal cleanup + FASTA derivation
bash scripts/data_preparation/clean_pdbs.sh merged/ cleaned/ /path/to/rosetta/tools/protein_tools/scripts/clean_pdb.py
python scripts/data_preparation/download_fastas.py merged/
python scripts/data_preparation/organize_fastas.py
python scripts/data_preparation/prepare_boltz_fastas.py

# 2. Predictions (SLURM batch)
sbatch scripts/run/af_batch.slurm
sbatch scripts/run/boltz_batch.slurm

# 3. Standalone AMBER on AF + Boltz outputs
sbatch scripts/relaxation/green_amber_l40s.slurm

# 4. Rosetta relaxation (810 runs/target × 257 targets)
sbatch scripts/relaxation/green_rosetta.slurm

# 5. Validation
sbatch scripts/validation/green_molprobity.slurm
sbatch scripts/validation/green_tmscore.slurm

# 6. Aggregation (canonical analysis lives in Protein_Relax_Pipeline/red_analysis/)
python scripts/analysis/aggregate_per_pipeline.py
```

For the canonical analysis pipeline (which consumes both Blue and Green output to produce the locked DB and figures), see `Protein_Relax_Pipeline/db/scripts/build_db.py` plus `build_db_supplements.py`.

## Computational resources (matched to Blue)

| Resource | Specification |
|---|---|
| AlphaFold 2.3.2 | NVIDIA RTX A6000, partition `csb_gpu_acc`, 80 GB RAM |
| Boltz-1 v0.4.1 | NVIDIA L40S 48 GB, partition `p_meiler_acc` |
| Rosetta 3.15 | CPU, partition `batch` (`p_csb_meiler`) |
| AMBER (standalone) | GPU OpenMM, on AlphaFold partition |

All SLURM array scripts include `#SBATCH --exclude=cn1340`.

## Resolved issues at lock

- 1ACB and 1ATN AMBER-crystal divergence resolved via `amber_relax_crystal_v5.py` (peptide-bond chain-split detection).
- 20 Blue crystal pre-Rosetta MP rows backfilled in the DB from Green crystal MP (PDBs verified byte-identical, MolProbity deterministic).
- Boltz OOM tier resolved via FASTA deduplication (135 targets had duplicate homo-multimer chains).
- AMBER X/Z atom-selection ambiguity resolved upstream (credited to Blue's diagnostic work, see `NOTEBOOK.md` 2026-02-21 entry).

Full chronology in `NOTEBOOK.md`. Snapshot 2026-04-27a is the steady state.

## License

MIT.

---

*Snapshot 2026-04-27a, locked at 100.000% on 2026-04-27. Companion to `Protein_Relax_Pipeline`. Last verified 2026-04-28.*
