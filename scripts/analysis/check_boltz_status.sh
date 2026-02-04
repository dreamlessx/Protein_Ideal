#!/bin/bash

echo "============================================"
echo "BOLTZ COMPLETION STATUS"
echo "============================================"
echo ""

# Check job status
echo "=== Running Jobs ==="
squeue -u $USER | grep boltz

echo ""
echo "=== Model Count per Structure ==="
echo ""

for pdb in 3BIW 3EO1 3L89 3R9A 4GXU 1FSK 5HYS; do
    # Find directory
    if [ -d "/data/p_csb_meiler/agarwm5/af_completed/$pdb" ]; then
        dir="/data/p_csb_meiler/agarwm5/af_completed/$pdb"
        loc="af_completed"
    elif [ -d "/data/p_csb_meiler/agarwm5/afset/$pdb" ]; then
        dir="/data/p_csb_meiler/agarwm5/afset/$pdb"
        loc="afset"
    else
        echo "✗ $pdb: NOT FOUND"
        continue
    fi
    
    pred_dir="$dir/boltz_out_dir/boltz_results_boltz_input/predictions/boltz_input"
    pdb_count=$(find "$pred_dir" -name "*.pdb" -type f 2>/dev/null | wc -l)
    
    if [ $pdb_count -eq 5 ]; then
        echo "✓ $pdb: $pdb_count/5 models COMPLETE ($loc)"
    elif [ $pdb_count -gt 0 ]; then
        echo "⚠ $pdb: $pdb_count/5 models ($loc)"
    else
        echo "✗ $pdb: 0/5 models ($loc)"
    fi
done

echo ""
echo "=== Recent Log Activity ==="
ls -lt /data/p_csb_meiler/agarwm5/scripts/logs/boltz_1m_*.out 2>/dev/null | head -5

echo ""
echo "============================================"
echo "Run this script periodically to monitor progress"
echo "============================================"
