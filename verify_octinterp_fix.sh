#!/bin/bash
set -e

echo "=== Testing octinterp.pc fix ==="

# Save current directory
WORK_DIR=$(pwd)
PREFIX="$WORK_DIR/output/bld/rattler-build_xeus-octave-wasm_1753877488/host_env_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placeho"

# Test 1: Show current pkg-config output
echo -e "\n1. Current pkg-config output for octinterp:"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --libs octinterp || echo "FAILED"

# Test 2: Fix the octinterp.pc file temporarily
echo -e "\n2. After fixing octinterp.pc:"
cp "$PREFIX/lib/pkgconfig/octinterp.pc" "$PREFIX/lib/pkgconfig/octinterp.pc.backup"
sed -i "s| /libinterp/liboctinterp\.a| -loctinterp|g" "$PREFIX/lib/pkgconfig/octinterp.pc"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --libs octinterp

# Test 3: Show combined octave + octinterp flags
echo -e "\n3. Combined octave + octinterp flags:"
PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig" pkg-config --static --libs octave octinterp

# Restore original
mv "$PREFIX/lib/pkgconfig/octinterp.pc.backup" "$PREFIX/lib/pkgconfig/octinterp.pc"

echo -e "\n=== Verify liboctinterp.a is actually there ==="
ls -la "$PREFIX/lib/octave/7.2.0/liboctinterp.a"