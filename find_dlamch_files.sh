#!/bin/bash
set -e

echo "=== Searching for all dlamch-related files ==="

# Search in the work directory for any dlamch files
echo -e "\n1. All files containing 'dlamch' in octave-wasm directories:"
find . -path "*/octave-wasm/*" -name "*dlamch*" -type f 2>/dev/null | head -20

echo -e "\n2. Checking if there's a plain dlamch.c or dlamch.o:"
find . -path "*/octave-wasm/*" \( -name "dlamch.c" -o -name "dlamch.o" \) -type f 2>/dev/null

echo -e "\n3. Looking in the clapack source directory:"
if [ -d "octave-wasm/third_party/lapack-3.4.2" ]; then
    find octave-wasm/third_party/lapack-3.4.2 -name "*dlamch*" -type f | grep -v ".f$" | head -20
fi

echo -e "\n4. Check what symbols are defined in lapacke_dlamch.o (if it exists):"
DLAMCH_OBJ=$(find . -name "lapacke_dlamch.o" -type f 2>/dev/null | head -1)
if [ -n "$DLAMCH_OBJ" ]; then
    echo "Found: $DLAMCH_OBJ"
    llvm-nm "$DLAMCH_OBJ" | grep -E "^[0-9a-f]+ [TtDdBb]" | head -10
else
    echo "No lapacke_dlamch.o found"
fi

echo -e "\n5. Search for the actual Fortran-to-C converted dlamch:"
find . -path "*/lapack-3.4.2/*" -name "*.c" -type f -exec grep -l "dlamch_" {} \; 2>/dev/null | grep -v lapacke | head -10