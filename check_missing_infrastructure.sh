#!/bin/bash
set -e

echo "=== Checking for missing LAPACK infrastructure functions ==="

PREFIX="$PWD/output/bld/rattler-build_xeus-octave-wasm_1753877488/host_env_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placehold_placeho"

echo -e "\n1. Checking for common LAPACK infrastructure functions:"
for func in dlamch slamch ilaenv xerbla lsame iparmq ieeeck; do
    echo -n "Checking $func: "
    if llvm-nm "$PREFIX/lib/libclapack.a" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
        echo "FOUND (defined)"
    elif llvm-nm "$PREFIX/lib/libclapack.a" 2>/dev/null | grep " U ${func}_\$" >/dev/null; then
        echo "UNDEFINED (needed but missing)"
    else
        echo "Not referenced"
    fi
done

echo -e "\n2. Check if these might be in libf2c.a instead:"
for func in dlamch slamch ilaenv xerbla lsame; do
    echo -n "Checking $func in libf2c.a: "
    if llvm-nm "$PREFIX/lib/libf2c.a" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
        echo "FOUND"
    else
        echo "Not found"
    fi
done

echo -e "\n3. Looking for any .o files that might define these functions:"
ar t "$PREFIX/lib/libclapack.a" | grep -E "(dlamch|slamch|ilaenv|xerbla|lsame|iparmq|ieeeck)" || echo "None found"

echo -e "\n=== Checking for BLAS functions ==="

echo -e "\n4. Checking common BLAS Level 1 functions:"
for func in daxpy dcopy ddot dnrm2 dscal dasum idamax drot drotg dswap; do
    echo -n "Checking $func: "
    found=false
    for lib in libclapack.a librefblas.a; do
        if [ -f "$PREFIX/lib/$lib" ]; then
            if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
                echo "FOUND in $lib"
                found=true
                break
            fi
        fi
    done
    if [ "$found" = false ]; then
        echo "NOT FOUND"
    fi
done

echo -e "\n5. Checking common BLAS Level 2 functions:"
for func in dgemv dger dsymv dsyr dtrmv dtrsv dsbmv dspmv; do
    echo -n "Checking $func: "
    found=false
    for lib in libclapack.a librefblas.a; do
        if [ -f "$PREFIX/lib/$lib" ]; then
            if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
                echo "FOUND in $lib"
                found=true
                break
            fi
        fi
    done
    if [ "$found" = false ]; then
        echo "NOT FOUND"
    fi
done

echo -e "\n6. Checking common BLAS Level 3 functions:"
for func in dgemm dsymm dsyrk dsyr2k dtrmm dtrsm; do
    echo -n "Checking $func: "
    found=false
    for lib in libclapack.a librefblas.a; do
        if [ -f "$PREFIX/lib/$lib" ]; then
            if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
                echo "FOUND in $lib"
                found=true
                break
            fi
        fi
    done
    if [ "$found" = false ]; then
        echo "NOT FOUND"
    fi
done

echo -e "\n7. Checking for complex BLAS functions (single precision):"
for func in caxpy cdotc cdotu cgemm cgemv; do
    echo -n "Checking $func: "
    found=false
    for lib in libclapack.a librefblas.a; do
        if [ -f "$PREFIX/lib/$lib" ]; then
            if llvm-nm "$PREFIX/lib/$lib" 2>/dev/null | grep -E "^[0-9a-f]+ [TtDdBb] ${func}_\$" >/dev/null; then
                echo "FOUND in $lib"
                found=true
                break
            fi
        fi
    done
    if [ "$found" = false ]; then
        echo "NOT FOUND"
    fi
done

echo -e "\n8. Check object files in librefblas.a:"
if [ -f "$PREFIX/lib/librefblas.a" ]; then
    echo "First 20 object files in librefblas.a:"
    ar t "$PREFIX/lib/librefblas.a" | head -20
else
    echo "librefblas.a not found!"
fi

echo -e "\n9. Summary of library sizes:"
for lib in libclapack.a librefblas.a libf2c.a; do
    if [ -f "$PREFIX/lib/$lib" ]; then
        size=$(ls -lh "$PREFIX/lib/$lib" | awk '{print $5}')
        count=$(ar t "$PREFIX/lib/$lib" | wc -l)
        echo "$lib: $size, $count object files"
    else
        echo "$lib: NOT FOUND"
    fi
done