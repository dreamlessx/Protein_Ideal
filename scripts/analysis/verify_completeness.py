#!/usr/bin/env python3
"""
Verify completeness of relaxed protein structures and sort into analysis/todo folders.

Strict criteria:
- Top-level: 6 protocol folders × 5 replicates each
- relax/AF: 5 ranked models × 6 protocols × 5 replicates each
- relax/Boltz: 5 boltz models × 6 protocols × 5 replicates each
"""

import os
import shutil
from pathlib import Path

# Define base paths
BASE_DIR = Path("/data/p_csb_meiler/agarwm5")
TEST_DIR = BASE_DIR / "todo"
ANALYSIS_DIR = BASE_DIR / "analysis"
TODO_DIR = BASE_DIR / "todot"

# Define expected protocols
PROTOCOLS = [
    "cartesian_beta",
    "cartesian_ref15",
    "dualspace_beta",
    "dualspace_ref15",
    "normal_beta",
    "normal_ref15"
]

NUM_REPLICATES = 5


def check_protocol_folder(protocol_path, prefix):
    """
    Check if a protocol folder has exactly 5 replicates.
    
    Args:
        protocol_path: Path to protocol folder
        prefix: Expected prefix for replicate files (e.g., "ranked_0", "1AK4")
    
    Returns:
        bool: True if all 5 replicates exist
    """
    if not protocol_path.exists():
        return False
    
    # Check for r1.pdb.gz through r5.pdb.gz
    for i in range(1, NUM_REPLICATES + 1):
        replicate_file = protocol_path / f"{prefix}_r{i}.pdb.gz"
        if not replicate_file.exists():
            return False
    
    return True


def check_top_level_protocols(protein_dir):
    """
    Check if top-level protocol folders all have 5 replicates.
    
    Args:
        protein_dir: Path to protein folder
    
    Returns:
        bool: True if all top-level protocols are complete
    """
    protein_name = protein_dir.name
    
    for protocol in PROTOCOLS:
        protocol_path = protein_dir / protocol
        if not check_protocol_folder(protocol_path, protein_name):
            return False
    
    return True


def check_relax_af(protein_dir):
    """
    Check if relax/AF folder has all ranked models with complete protocols.
    
    Args:
        protein_dir: Path to protein folder
    
    Returns:
        bool: True if relax/AF is complete
    """
    relax_af_dir = protein_dir / "relax" / "AF"
    
    if not relax_af_dir.exists():
        return False
    
    # Check all 5 ranked models
    for i in range(5):
        ranked_dir = relax_af_dir / f"ranked_{i}"
        if not ranked_dir.exists():
            return False
        
        # Check all 6 protocols for this ranked model
        for protocol in PROTOCOLS:
            protocol_path = ranked_dir / protocol
            if not check_protocol_folder(protocol_path, f"ranked_{i}"):
                return False
    
    return True


def check_relax_boltz(protein_dir):
    """
    Check if relax/Boltz folder has all boltz models with complete protocols.
    
    Args:
        protein_dir: Path to protein folder
    
    Returns:
        bool: True if relax/Boltz is complete
    """
    relax_boltz_dir = protein_dir / "relax" / "Boltz"
    
    if not relax_boltz_dir.exists():
        return False
    
    # Check all 5 boltz models
    for i in range(5):
        boltz_dir = relax_boltz_dir / f"boltz_input_model_{i}"
        if not boltz_dir.exists():
            return False
        
        # Check all 6 protocols for this boltz model
        for protocol in PROTOCOLS:
            protocol_path = boltz_dir / protocol
            if not check_protocol_folder(protocol_path, f"boltz_input_model_{i}"):
                return False
    
    return True


def verify_protein_folder(protein_dir):
    """
    Verify that a protein folder meets all strict completeness criteria.
    
    Args:
        protein_dir: Path to protein folder
    
    Returns:
        tuple: (is_complete, missing_parts) where missing_parts is a list of issues
    """
    missing = []
    
    # Check top-level protocols
    if not check_top_level_protocols(protein_dir):
        missing.append("top-level protocols")
    
    # Check relax/AF
    if not check_relax_af(protein_dir):
        missing.append("relax/AF")
    
    # Check relax/Boltz
    if not check_relax_boltz(protein_dir):
        missing.append("relax/Boltz")
    
    is_complete = len(missing) == 0
    return is_complete, missing


def main():
    """Main verification and sorting workflow."""
    
    # Create analysis and todo directories
    ANALYSIS_DIR.mkdir(exist_ok=True)
    TODO_DIR.mkdir(exist_ok=True)
    
    print("Starting verification of protein structures...")
    print(f"Test directory: {TEST_DIR}")
    print(f"Analysis directory: {ANALYSIS_DIR}")
    print(f"Todo directory: {TODO_DIR}")
    print("-" * 80)
    
    # Get all protein folders
    protein_folders = sorted([d for d in TEST_DIR.iterdir() if d.is_dir()])
    
    complete_count = 0
    incomplete_count = 0
    
    for protein_dir in protein_folders:
        protein_name = protein_dir.name
        print(f"\nChecking {protein_name}...")
        
        is_complete, missing_parts = verify_protein_folder(protein_dir)
        
        if is_complete:
            print(f"  ✓ COMPLETE - copying to analysis/")
            dest = ANALYSIS_DIR / protein_name
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(protein_dir, dest)
            complete_count += 1
        else:
            print(f"  ✗ INCOMPLETE - copying to todo/")
            print(f"    Missing: {', '.join(missing_parts)}")
            dest = TODO_DIR / protein_name
            if dest.exists():
                shutil.rmtree(dest)
            shutil.copytree(protein_dir, dest)
            incomplete_count += 1
    
    print("\n" + "=" * 80)
    print(f"SUMMARY:")
    print(f"  Complete proteins (→ analysis/): {complete_count}")
    print(f"  Incomplete proteins (→ todo/): {incomplete_count}")
    print(f"  Total processed: {complete_count + incomplete_count}")
    print("=" * 80)


if __name__ == "__main__":
    main()
