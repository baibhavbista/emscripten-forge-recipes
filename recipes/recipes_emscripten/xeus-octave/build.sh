#!/bin/bash
set -ex

# --- FIX 1: Correct malformed pkg-config files ---
# This is necessary because Octave's WASM build generates incorrect paths
echo "Fixing pkg-config files..."
sed -i 's| /libinterp/liboctinterp.a| -loctinterp|g' $PREFIX/lib/pkgconfig/octinterp.pc
sed -i 's| /liboctave/liboctave.a| -loctave|g' $PREFIX/lib/pkgconfig/octave.pc

# Add CLAPACK back to the pkg-config files since we need it for missing symbols
# Note: We'll rely on --allow-multiple-definition to handle any duplicates
sed -i 's|Libs: \(.*\)|Libs: \1 -lclapack_all -lpcre2-8 -lf2c -lm|g' $PREFIX/lib/pkgconfig/octinterp.pc
sed -i 's|Libs: \(.*\)|Libs: \1 -lclapack_all -lpcre2-8 -lf2c -lm|g' $PREFIX/lib/pkgconfig/octave.pc

# Verify the pkg-config fixes
echo "Verifying pkg-config fixes..."
echo "octinterp.pc:"
grep "Libs:" $PREFIX/lib/pkgconfig/octinterp.pc
echo "octave.pc:"
grep "Libs:" $PREFIX/lib/pkgconfig/octave.pc

# --- FIX 2: Remove thread stubs from Octave's static libraries ---
# The Octave WASM build creates liboctave_stubs.a (containing thread stubs for disabled threading)
# and this stub library gets incorrectly embedded inside the main static libraries.
# The wasm-ld linker will fail if it finds these embedded archives.
echo "Cleaning thread stubs from Octave WASM libraries..."
ar d $PREFIX/lib/octave/9.4.0/liboctinterp.a liboctave_stubs.a 2>/dev/null || true
ar d $PREFIX/lib/octave/9.4.0/liboctave.a liboctave_stubs.a 2>/dev/null || true

# Verify stub removal
echo "Verifying stub removal..."
ar t $PREFIX/lib/octave/9.4.0/liboctinterp.a | grep "liboctave_stubs.a" || echo "liboctave_stubs.a successfully removed from liboctinterp.a"
ar t $PREFIX/lib/octave/9.4.0/liboctave.a | grep "liboctave_stubs.a" || echo "liboctave_stubs.a successfully removed from liboctave.a"

# --- FIX 3: Verify Octave contains BLAS/LAPACK symbols ---
echo "Checking if Octave contains BLAS/LAPACK symbols..."
nm -g $PREFIX/lib/octave/9.4.0/liboctave.a 2>/dev/null | grep -E "T.*gemm" | head -5 || echo "Warning: Could not find BLAS symbols in liboctave.a"

# --- FIX 4: NO LONGER HIDING CLAPACK ---
# We need CLAPACK for symbols that Octave doesn't provide
# The --allow-multiple-definition flag will handle any duplicate symbols
echo "CLAPACK will remain available for linking..."

# Commented out the hiding logic:
# echo "Hiding CLAPACK to prevent duplicate symbols..."
# if [ -f "$PREFIX/lib/libclapack_all.a" ]; then
#     mkdir -p $PREFIX/lib/.hidden_clapack
#     mv $PREFIX/lib/libclapack_all.a $PREFIX/lib/.hidden_clapack/
#     echo "Moved libclapack_all.a to hidden directory"
# fi
# 
# # Also hide any pkg-config files that might reference CLAPACK
# if [ -f "$PREFIX/lib/pkgconfig/clapack.pc" ]; then
#     mv $PREFIX/lib/pkgconfig/clapack.pc $PREFIX/lib/pkgconfig/clapack.pc.bak
# fi
# 
# # Hide any cmake files that might find CLAPACK
# if [ -d "$PREFIX/lib/cmake/clapack" ]; then
#     mv $PREFIX/lib/cmake/clapack $PREFIX/lib/cmake/clapack.bak
# fi

# --- Build Process ---

# Clear any existing build directory to ensure a clean configuration
echo "Cleaning build directory..."
rm -rf build
rm -f CMakeCache.txt

# Add linker flags to allow multiple definitions (required by Octave)
export LDFLAGS="${LDFLAGS} -Wl,--allow-multiple-definition"

# Ensure pkg-config can find all dependencies
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"

# Debug: Show what pkg-config will return for Octave
echo "pkg-config output for octave:"
pkg-config --libs octave || true
echo "pkg-config output for octinterp:"
pkg-config --libs octinterp || true

# Configure the build using emcmake
# Now CLAPACK will be available and can be found by CMake if needed
emcmake cmake ${CMAKE_ARGS} \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_SYSTEM_NAME=Emscripten \
    -D XEUS_OCTAVE_BUILD_SHARED=OFF \
    -D XEUS_OCTAVE_BUILD_STATIC=ON \
    -D XEUS_OCTAVE_USE_SHARED_XEUS=OFF \
    -D XEUS_OCTAVE_DISABLE_ARCH_NATIVE=ON \
    -D CMAKE_INSTALL_PREFIX=$PREFIX \
    -D CMAKE_EXE_LINKER_FLAGS="-Wl,--allow-multiple-definition" \
    -D CMAKE_MODULE_LINKER_FLAGS="-Wl,--allow-multiple-definition" \
    -D CMAKE_FIND_DEBUG_MODE=ON \
    -D CMAKE_VERBOSE_MAKEFILE=ON \
    -D ZLIB_INCLUDE_DIR=$PREFIX/include \
    -D ZLIB_LIBRARY=$PREFIX/lib/libz.a \
    -D PNG_PNG_INCLUDE_DIR=$PREFIX/include \
    -D PNG_LIBRARY=$PREFIX/lib/libpng.a \
    -S . -B build

# Check what BLAS/LAPACK cmake found (if any)
echo "Checking CMake BLAS/LAPACK detection:"
grep -i "blas\|lapack" build/CMakeCache.txt || echo "No BLAS/LAPACK entries in CMakeCache.txt"

# Build with emmake
emmake make -C build -j${CPU_COUNT}

# Install the built files
make -C build install

# --- FIX 5: No restoration needed since we didn't hide anything ---
# Commented out the restoration logic:
# echo "Restoring hidden files..."
# if [ -d "$PREFIX/lib/.hidden_clapack" ]; then
#     mv $PREFIX/lib/.hidden_clapack/libclapack_all.a $PREFIX/lib/
#     rmdir $PREFIX/lib/.hidden_clapack
# fi
# 
# # Restore pkg-config files
# if [ -f "$PREFIX/lib/pkgconfig/clapack.pc.bak" ]; then
#     mv $PREFIX/lib/pkgconfig/clapack.pc.bak $PREFIX/lib/pkgconfig/clapack.pc
# fi
# 
# # Restore cmake files
# if [ -d "$PREFIX/lib/cmake/clapack.bak" ]; then
#     mv $PREFIX/lib/cmake/clapack.bak $PREFIX/lib/cmake/clapack
# fi

echo "Build completed successfully!"