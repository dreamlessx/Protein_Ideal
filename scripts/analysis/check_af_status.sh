#!/bin/bash
# Check AF resume job status and results
# Usage: bash check_af_resume.sh [JOB_ID]

JOBID=${1:-8758604}
DIRLIST=/data/p_csb_meiler/agarwm5/scripts/af_dirlist.txt
TOTAL=$(wc -l < "$DIRLIST")

echo "========================================"
echo "AF Resume Job Status (Job $JOBID)"
echo "========================================"

# Count completed, failed, running, pending
completed=0
failed=0
needs_run=0
complete_list=""
failed_list=""
needs_list=""

for i in $(seq 1 "$TOTAL"); do
    d=$(sed -n "${i}p" "$DIRLIST")
    name=$(basename "$d")

    if compgen -G "$d/af_out/*/ranking_debug.json" > /dev/null 2>&1; then
        completed=$((completed + 1))
        complete_list="$complete_list $name"
    else
        ranked=$(find "$d" -name "ranked_*.pdb" 2>/dev/null | wc -l)
        unrelaxed=$(find "$d" -name "unrelaxed_model_*.pdb" 2>/dev/null | wc -l)
        if [ "$unrelaxed" -gt 0 ]; then
            failed=$((failed + 1))
            failed_list="$failed_list $name(unrelaxed=$unrelaxed,ranked=$ranked)"
        else
            needs_run=$((needs_run + 1))
            needs_list="$needs_list $name"
        fi
    fi
done

echo ""
echo "COMPLETED: $completed / $TOTAL"
echo "PARTIAL (has models, no ranking): $failed"
echo "NEEDS FULL RUN: $needs_run"
echo ""

if [ -n "$complete_list" ]; then
    echo "--- Completed targets ---"
    echo "$complete_list" | tr ' ' '\n' | sort
    echo ""
fi

if [ -n "$failed_list" ]; then
    echo "--- Partial targets (need rerun) ---"
    echo "$failed_list" | tr ' ' '\n' | sort
    echo ""
fi

if [ -n "$needs_list" ]; then
    echo "--- Needs full run ---"
    echo "$needs_list" | tr ' ' '\n' | sort
    echo ""
fi

# Show SLURM job status
echo "--- SLURM job status ---"
sacct -j "$JOBID" --format=JobID%20,State%12,Elapsed%12,ExitCode%8,NodeList%15 2>/dev/null | head -50
