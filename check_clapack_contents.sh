#!/bin/bash
set -e

echo "=== Analyzing CLAPACK library contents ==="

PREFIX="$PWD/output/bld/rattler-build_xeus-octave-wasm_1753877488/host_env_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placeho"

echo -e "\n1. Looking for dlamch-related object files in libclapack.a:"
ar t "$PREFIX/lib/libclapack.a" | grep -i dlamch || echo "No dlamch objects found"

echo -e "\n2. Looking for any machine parameter functions:"
ar t "$PREFIX/lib/libclapack.a" | grep -E "(lamch|mach)" | head -20

echo -e "\n3. Check if we have ilaenv (another important LAPACK function):"
llvm-nm "$PREFIX/lib/libclapack.a" | grep -i ilaenv | head -5

echo -e "\n4. List first 50 object files to understand naming pattern:"
ar t "$PREFIX/lib/libclapack.a" | head -50

echo -e "\n=== Checking BLAS functions in libraries ==="

echo -e "\n5. Checking if BLAS functions are in libclapack.a or librefblas.a:"
echo "Checking for dgemm (key BLAS Level 3 function):"
for lib in libclapack.a librefblas.a; do
    if [ -f "$PREFIX/lib/$lib" ]; then
        echo -n "  In $lib: "
        if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] dgemm_\$" >/dev/null; then
            echo "FOUND"
        else
            echo "NOT FOUND"
        fi
    fi
done

echo -e "\n6. Sample of BLAS Level 1 functions in each library:"
for func in daxpy ddot dnrm2; do
    echo "Checking $func:"
    for lib in libclapack.a librefblas.a; do
        if [ -f "$PREFIX/lib/$lib" ]; then
            echo -n "  In $lib: "
            if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
                echo "FOUND"
            else
                echo "NOT FOUND"
            fi
        fi
    done
done

echo -e "\n7. Contents of librefblas.a (first 30 files):"
if [ -f "$PREFIX/lib/librefblas.a" ]; then
    ar t "$PREFIX/lib/librefblas.a" | head -30
else
    echo "librefblas.a not found!"
fi

echo -e "\n8. Check for complex BLAS functions:"
for func in cgemm zgemm; do
    echo "Checking $func (complex matrix multiply):"
    for lib in libclapack.a librefblas.a; do
        if [ -f "$PREFIX/lib/$lib" ]; then
            echo -n "  In $lib: "
            if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
                echo "FOUND"
            else
                echo "NOT FOUND"
            fi
        fi
    done
done

echo -e "\n9. Library statistics:"
for lib in libclapack.a librefblas.a libf2c.a; do
    if [ -f "$PREFIX/lib/$lib" ]; then
        size=$(ls -lh "$PREFIX/lib/$lib" | awk '{print $5}')
        count=$(ar t "$PREFIX/lib/$lib" | wc -l)
        echo "$lib: $size, $count object files"
    else
        echo "$lib: NOT FOUND"
    fi
done

echo -e "\n10. Check for LAPACK auxiliary routines that might be missing:"
for func in xerbla lsame disnan dlaisnan; do
    echo -n "Checking $func: "
    found=false
    for lib in libclapack.a libf2c.a; do
        if [ -f "$PREFIX/lib/$lib" ]; then
            if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
                echo "FOUND in $lib"
                found=true
                break
            fi
        fi
    done
    if [ "$found" = false ]; then
        if llvm-nm "$PREFIX/lib/libclapack.a" 2>/dev/null | grep " U ${func}_\$" >/dev/null; then
            echo "UNDEFINED (needed but missing)"
        else
            echo "NOT FOUND"
        fi
    fi
done