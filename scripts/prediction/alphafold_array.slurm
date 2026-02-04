#!/bin/bash --norc

#SBATCH --constraint=csbtmp
#SBATCH --account=csb_gpu_acc
#SBATCH --partition=batch_gpu
#SBATCH --nodes=1
#SBATCH --ntasks=6
#SBATCH --gres=gpu:nvidia_rtx_a6000:1
#SBATCH --mem=40G
#SBATCH --time=48:00:00
#SBATCH --job-name=af_array
#SBATCH --output=logs/af_array_%A_%a.out
#SBATCH --error=logs/af_array_%A_%a.err

# AlphaFold 2.3.2 Array Job
# Based on working template from Jarrod Smith <jarrod.smith@vanderbilt.edu>
#
# Submit with: sbatch --array=1-N alphafold_array.slurm
#   N = number of lines in af_dirlist.txt

# ---- Configuration ----
AF2_MINICONDA=/sb/apps/alphafold232/miniconda3
AF2_DATADIR=/csbtmp/alphafold-data.230
AF2_REPO=/sb/apps/alphafold232/alphafold
DIRLIST_FILE=af_dirlist.txt

# ---- Get directory for this array task ----
CALCDIR=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "$DIRLIST_FILE")

if [[ -z "$CALCDIR" ]]; then
    echo "ERROR: Could not read directory for task $SLURM_ARRAY_TASK_ID"
    exit 1
fi

TARGET=$(basename "$CALCDIR")

cd $CALCDIR

nvidia-smi

echo -n "Running on "
echo $SLURM_JOB_NODELIST
echo "Target: $TARGET"
echo "Directory: $CALCDIR"

# ---- Check if already completed ----
if compgen -G "$CALCDIR/af_out/*/ranking_debug.json" > /dev/null 2>&1; then
    echo "SKIP: $TARGET already complete."
    exit 0
fi

# ---- Find FASTA file ----
if [[ -s sequence.fasta ]]; then
    FASTA=sequence.fasta
elif [[ -s boltz_input.fasta ]]; then
    FASTA=boltz_input.fasta
else
    echo "ERROR: No FASTA found in $CALCDIR"
    exit 2
fi

echo "FASTA: $FASTA"

# ---- Determine model preset ----
SEQCOUNT=$(grep -c '^>' "$FASTA" || true)
echo "Sequences: $SEQCOUNT"

# Activate CSB Alphafold2 miniconda environment
source $AF2_MINICONDA/bin/activate af232
export LD_LIBRARY_PATH=$AF2_MINICONDA/envs/af232/lib:$LD_LIBRARY_PATH

# ---- Build and run command based on monomer vs multimer ----
if (( SEQCOUNT > 1 )); then
    echo "Running as MULTIMER"
    python $AF2_REPO/run_alphafold.py \
        --fasta_paths=$FASTA \
        --max_template_date=9999-12-31 \
        --data_dir=$AF2_DATADIR \
        --output_dir=$CALCDIR/af_out \
        --model_preset=multimer \
        --use_gpu_relax \
        --uniref90_database_path=$AF2_DATADIR/uniref90/uniref90.fasta \
        --mgnify_database_path=$AF2_DATADIR/mgnify/mgy_clusters_2022_05.fa \
        --uniref30_database_path=$AF2_DATADIR/uniref30/UniRef30_2021_03 \
        --bfd_database_path=$AF2_DATADIR/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt \
        --pdb_seqres_database_path=$AF2_DATADIR/pdb_seqres/pdb_seqres.txt \
        --uniprot_database_path=$AF2_DATADIR/uniprot/uniprot.fasta \
        --template_mmcif_dir=$AF2_DATADIR/pdb_mmcif/mmcif_files \
        --obsolete_pdbs_path=$AF2_DATADIR/pdb_mmcif/obsolete.dat \
        --num_multimer_predictions_per_model=1
else
    echo "Running as MONOMER"
    python $AF2_REPO/run_alphafold.py \
        --fasta_paths=$FASTA \
        --max_template_date=9999-12-31 \
        --data_dir=$AF2_DATADIR \
        --output_dir=$CALCDIR/af_out \
        --use_gpu_relax \
        --uniref90_database_path=$AF2_DATADIR/uniref90/uniref90.fasta \
        --mgnify_database_path=$AF2_DATADIR/mgnify/mgy_clusters_2022_05.fa \
        --uniref30_database_path=$AF2_DATADIR/uniref30/UniRef30_2021_03 \
        --bfd_database_path=$AF2_DATADIR/bfd/bfd_metaclust_clu_complete_id30_c90_final_seq.sorted_opt \
        --pdb70_database_path=$AF2_DATADIR/pdb70/pdb70 \
        --template_mmcif_dir=$AF2_DATADIR/pdb_mmcif/mmcif_files \
        --obsolete_pdbs_path=$AF2_DATADIR/pdb_mmcif/obsolete.dat
fi
