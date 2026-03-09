#!/bin/bash --norc
#SBATCH --constraint=csbtmp
#SBATCH --account=csb_gpu_acc
#SBATCH --partition=batch_gpu
#SBATCH --nodes=1
#SBATCH --ntasks=6
#SBATCH --gres=gpu:nvidia_rtx_a6000:1
#SBATCH --mem=64G
#SBATCH --time=48:00:00
#SBATCH --job-name=green_af_1ktz
#SBATCH --output=logs/green_af_1ktz_%j.out
#SBATCH --error=logs/green_af_1ktz_%j.err

# 1KTZ: max_template_date=1900-01-01 (AF2.3.2 template bug workaround)
# Must run on A6000 (L40S has CUDA/JAX incompatibility with AF2.3.2)

set -uo pipefail

AF2_MINICONDA=/sb/apps/alphafold232/miniconda3
AF2_DATADIR=/csbtmp/alphafold-data.230
AF2_REPO=/sb/apps/alphafold232/alphafold

D="/panfs/accrepfs.vampire/data/p_csb_meiler/agarwm5/protein_ideal_test/benchmarking/data/1KTZ"
cd "$D"

FASTA=sequence.fasta
SEQCOUNT=$(grep -c '^>' "$FASTA")
echo "1KTZ: $SEQCOUNT sequences, A6000, max_template_date=1900-01-01"

source $AF2_MINICONDA/bin/activate af232
export LD_LIBRARY_PATH=$AF2_MINICONDA/envs/af232/lib:${LD_LIBRARY_PATH:-}

nvidia-smi
echo "Node: $SLURM_JOB_NODELIST"

python $AF2_REPO/run_alphafold.py \
    --fasta_paths=$FASTA \
    --max_template_date=1900-01-01 \
    --data_dir=$AF2_DATADIR \
    --output_dir=$D/af_out \
    --model_preset=multimer \
    --db_preset=reduced_dbs \
    --nouse_gpu_relax \
    --models_to_relax=all \
    --uniref90_database_path=$AF2_DATADIR/uniref90/uniref90.fasta \
    --mgnify_database_path=$AF2_DATADIR/mgnify/mgy_clusters_2022_05.fa \
    --template_mmcif_dir=$AF2_DATADIR/pdb_mmcif/mmcif_files \
    --obsolete_pdbs_path=$AF2_DATADIR/pdb_mmcif/obsolete.dat \
    --small_bfd_database_path=$AF2_DATADIR/small_bfd/bfd-first_non_consensus_sequences.fasta \
    --pdb_seqres_database_path=$AF2_DATADIR/pdb_seqres/pdb_seqres.txt \
    --uniprot_database_path=$AF2_DATADIR/uniprot/uniprot.fasta \
    --num_multimer_predictions_per_model=1

echo "AF done for 1KTZ"

# Cleanup intermediates but KEEP ranked + unrelaxed models
cd af_out/sequence 2>/dev/null || cd af_out/*/
rm -rf msas/ 2>/dev/null
rm -f features.pkl result_model_*.pkl timings.json 2>/dev/null

echo "1KTZ complete"
