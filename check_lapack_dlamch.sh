#!/bin/bash
set -e

echo "=== Checking for dlamch in LAPACK 3.4.2 ==="

# Save current directory
WORK_DIR=$(pwd)
PREFIX="$WORK_DIR/output/bld/rattler-build_xeus-octave-wasm_1753877488/host_env_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placeho"

# Check all LAPACK-related libraries for dlamch
echo -e "\n1. Searching for dlamch in all .a files:"
for lib in "$PREFIX/lib"/*.a; do
    if [ -f "$lib" ]; then
        echo -e "\nChecking $(basename $lib):"
        llvm-nm "$lib" 2>/dev/null | grep -i "dlamch" | head -5 || echo "  No dlamch found"
    fi
done

# Check specifically in libclapack.a for all symbols it defines (not just undefined)
echo -e "\n2. All defined symbols in libclapack.a containing 'lamch':"
llvm-nm "$PREFIX/lib/libclapack.a" | grep -E "^[0-9a-f]+ [TtDdBb]" | grep -i "lamch" || echo "None found"

# Check for F2C naming convention issues
echo -e "\n3. Checking for F2C naming variants:"
llvm-nm "$PREFIX/lib/libclapack.a" | grep -E "(dlamch|DLAMCH|dlamch__)" || echo "None found"

# List all object files in libclapack.a
echo -e "\n4. All object files in libclapack.a (first 20):"
ar t "$PREFIX/lib/libclapack.a" | head -20

# Check if dlamch might be in libf2c.a
echo -e "\n5. Checking libf2c.a for dlamch:"
llvm-nm "$PREFIX/lib/libf2c.a" | grep -i "dlamch" || echo "Not found in libf2c.a"