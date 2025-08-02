#!/bin/bash
set -ex

# Build script for xeus-octave WebAssembly kernel
# 
# This script works around structural issues in the octave-build-static package:
# 1. Extracts embedded archives (libclapack.a, librefblas.a, libf2c.a) from liboctave.a
# 2. Rebuilds clean Octave archives containing only object files
# 3. Includes SuiteSparse dependencies (now properly built as static libraries)
# 4. Configures CMake with corrected paths and complete linker flags
#
# NOTE: Full functionality including sparse matrix operations is now available.

# --- Phase 1: Extract Embedded Archives ---
# The octave-build-static package has a structural issue:
# Valid archives (libclapack.a, librefblas.a, libf2c.a) are embedded inside liboctave.a
#
# Our approach:
# 1. Extract the embedded archives from liboctave.a and liboctinterp.a
# 2. Place them in $PREFIX/lib where the linker can find them
# 3. Rebuild clean liboctave.a and liboctinterp.a with only .o files
# 4. Use all dependencies including SuiteSparse (now properly built as static libraries)

# FIXME:maybe we need to stub the threads as we did previously

echo "--- Starting archive extraction and cleanup ---"
OCTAVE_LIB_DIR="$PREFIX/lib/octave/7.2.0"

# Create temporary directories for extraction
TEMP_OCTAVE_DIR="temp_octave_extract"
TEMP_INTERP_DIR="temp_interp_extract"
mkdir -p "$TEMP_OCTAVE_DIR" "$TEMP_INTERP_DIR"

# Extract all members from liboctave.a
echo "Extracting contents of liboctave.a..."
(cd "$TEMP_OCTAVE_DIR" && ar -x "$OCTAVE_LIB_DIR/liboctave.a")

# Extract all members from liboctinterp.a
echo "Extracting contents of liboctinterp.a..."
(cd "$TEMP_INTERP_DIR" && ar -x "$OCTAVE_LIB_DIR/liboctinterp.a")

# Move the embedded archives to $PREFIX/lib
echo "Moving embedded archives to $PREFIX/lib/..."
for archive in libclapack.a librefblas.a libf2c.a; do
    # Check both temp directories and move if found
    if [ -f "$TEMP_OCTAVE_DIR/$archive" ]; then
        echo "Found $archive in liboctave.a, moving to $PREFIX/lib/"
        mv "$TEMP_OCTAVE_DIR/$archive" "$PREFIX/lib/"
    elif [ -f "$TEMP_INTERP_DIR/$archive" ]; then
        echo "Found $archive in liboctinterp.a, moving to $PREFIX/lib/"
        mv "$TEMP_INTERP_DIR/$archive" "$PREFIX/lib/"
    fi
done

# Also move any lt*- prefixed versions (libtool artifacts)
for archive in lt*-*.a; do
    if [ -f "$TEMP_OCTAVE_DIR/$archive" ]; then
        echo "Removing libtool artifact: $archive"
        rm "$TEMP_OCTAVE_DIR/$archive"
    fi
    if [ -f "$TEMP_INTERP_DIR/$archive" ]; then
        echo "Removing libtool artifact: $archive"
        rm "$TEMP_INTERP_DIR/$archive"
    fi
done

# Rebuild clean liboctave.a with only .o files
echo "Rebuilding clean liboctave.a..."
rm -f "$OCTAVE_LIB_DIR/liboctave.a"
(cd "$TEMP_OCTAVE_DIR" && ar -r "$OCTAVE_LIB_DIR/liboctave.a" *.o)

# Rebuild clean liboctinterp.a with only .o files
echo "Rebuilding clean liboctinterp.a..."
rm -f "$OCTAVE_LIB_DIR/liboctinterp.a"
(cd "$TEMP_INTERP_DIR" && ar -r "$OCTAVE_LIB_DIR/liboctinterp.a" *.o)

# Clean up temporary directories
rm -rf "$TEMP_OCTAVE_DIR" "$TEMP_INTERP_DIR"

# --- Verification Step ---
echo "--- Verifying extracted and rebuilt libraries ---"

# Check that extracted archives are valid
echo "Checking extracted archives in $PREFIX/lib/..."
EXTRACTED_LIBS=("libclapack.a" "librefblas.a" "libf2c.a")
for lib in "${EXTRACTED_LIBS[@]}"; do
    if [ ! -f "$PREFIX/lib/$lib" ]; then
        echo "ERROR: Expected archive not found: $PREFIX/lib/$lib"
        exit 1
    else
        echo "Found: $lib ($(file -b "$PREFIX/lib/$lib" | head -1))"
        # Verify it's a valid archive
        if ! ar -t "$PREFIX/lib/$lib" >/dev/null 2>&1; then
            echo "ERROR: $lib is not a valid archive!"
            exit 1
        fi
    fi
done

# Also verify libpcre.a exists
if [ ! -f "$PREFIX/lib/libpcre.a" ]; then
    echo "ERROR: libpcre.a not found in $PREFIX/lib/"
    exit 1
else
    echo "Found: libpcre.a"
fi

# Verify the rebuilt Octave archives contain only .o files
echo "Verifying rebuilt Octave archives..."
for archive in "$OCTAVE_LIB_DIR/liboctave.a" "$OCTAVE_LIB_DIR/liboctinterp.a"; do
    if ar -t "$archive" | grep -q "\.a$"; then
        echo "ERROR: $archive still contains .a files after rebuild!"
        exit 1
    else
        echo "$(basename $archive) is clean (contains only .o files)"
    fi
done

echo "--- Archive extraction and cleanup complete ---"

# --- Verify critical LAPACK functions exist ---
echo "--- Checking for critical LAPACK infrastructure functions ---"
CRITICAL_FUNCTIONS=("dlamch_" "slamch_" "ilaenv_" "lsame_" "zgejsv_" "cgejsv_")
MISSING_FUNCTIONS=""

for func in "${CRITICAL_FUNCTIONS[@]}"; do
    if ! llvm-nm "$PREFIX/lib/libclapack.a" 2>/dev/null | grep -q " T $func"; then
        MISSING_FUNCTIONS="$MISSING_FUNCTIONS $func"
    fi
done

if [ -n "$MISSING_FUNCTIONS" ]; then
    # I think this happens only for zgejsv_ and cgejsv_
    echo "WARNING: Critical LAPACK functions missing from libclapack.a:$MISSING_FUNCTIONS"
    echo "Will compile stub implementations for missing functions..."
    
    # Create a temporary C file with only the missing functions
    cat > lapack_missing_temp.c << 'EOF'
/* Stub implementations for missing LAPACK infrastructure functions */
#include <float.h>

EOF
    
    # Add implementations only for missing functions
    # Note: xerbla_ is already provided by librefblas.a and liboctave.a
    # so we don't need to provide it
    
    for func in $MISSING_FUNCTIONS; do
        case $func in
            "dlamch_")
                cat >> lapack_missing_temp.c << 'EOF'
double dlamch_(char* cmach) {
    if (*cmach == 'E' || *cmach == 'e') return DBL_EPSILON;
    else if (*cmach == 'S' || *cmach == 's') return DBL_MIN;
    else if (*cmach == 'B' || *cmach == 'b') return 2.0;
    else if (*cmach == 'P' || *cmach == 'p') return DBL_EPSILON;
    else if (*cmach == 'R' || *cmach == 'r') return 1.0;
    else if (*cmach == 'M' || *cmach == 'm') return -DBL_MAX;
    else if (*cmach == 'U' || *cmach == 'u') return DBL_MIN;
    else if (*cmach == 'L' || *cmach == 'l') return DBL_MAX;
    else if (*cmach == 'O' || *cmach == 'o') return 1.0;
    return 0.0;
}
EOF
                ;;
            "slamch_")
                cat >> lapack_missing_temp.c << 'EOF'
float slamch_(char* cmach) {
    if (*cmach == 'E' || *cmach == 'e') return FLT_EPSILON;
    else if (*cmach == 'S' || *cmach == 's') return FLT_MIN;
    else if (*cmach == 'B' || *cmach == 'b') return 2.0f;
    else if (*cmach == 'P' || *cmach == 'p') return FLT_EPSILON;
    else if (*cmach == 'R' || *cmach == 'r') return 1.0f;
    else if (*cmach == 'M' || *cmach == 'm') return -FLT_MAX;
    else if (*cmach == 'U' || *cmach == 'u') return FLT_MIN;
    else if (*cmach == 'L' || *cmach == 'l') return FLT_MAX;
    else if (*cmach == 'O' || *cmach == 'o') return 1.0f;
    return 0.0f;
}
EOF
                ;;
            "ilaenv_")
                cat >> lapack_missing_temp.c << 'EOF'
int ilaenv_(int* ispec, char* name, char* opts, int* n1, int* n2, int* n3, int* n4) {
    if (*ispec == 1) return 64;      // Optimal blocksize
    else if (*ispec == 2) return 2;  // Minimum blocksize
    else if (*ispec == 3) return 128; // Crossover point
    else if (*ispec == 4) return 16;  // Number of shifts
    else if (*ispec == 6) return 1;   // Used by xHSEQR
    else if (*ispec == 9) return 25;  // Maximum size for using unblocked code
    else if (*ispec == 10) return 1;  // IEEE NaN arithmetic can be trusted
    else if (*ispec == 11) return 1;  // Infinity arithmetic can be trusted
    return -1;
}
EOF
                ;;
            "lsame_")
                cat >> lapack_missing_temp.c << 'EOF'
int lsame_(char* ca, char* cb) {
    char cha = *ca;
    char chb = *cb;
    if (cha >= 'a' && cha <= 'z') cha = cha - 'a' + 'A';
    if (chb >= 'a' && chb <= 'z') chb = chb - 'a' + 'A';
    return (cha == chb) ? 1 : 0;
}
EOF
                ;;
            "zgejsv_")
                cat >> lapack_missing_temp.c << 'EOF'
#include <stdio.h>
/* Stub for complex*16 Jacobi SVD - not implemented */
/* Note: f2c version returns int and may have extra string length parameters */
int zgejsv_(char* joba, char* jobu, char* jobv, char* jobr, char* jobt, char* jobp,
            int* m, int* n, void* a, int* lda, double* sva, void* u, int* ldu,
            void* v, int* ldv, void* cwork, int* lwork, double* work, int* lrwork,
            int* iwork, int* info,
            int joba_len, int jobu_len, int jobv_len, int jobr_len, int jobt_len, int jobp_len) {
    fprintf(stderr, "ERROR: zgejsv_ (complex Jacobi SVD) is not implemented in this build\n");
    *info = -999;  // Signal error
    return 0;
}
EOF
                ;;
            "cgejsv_")
                cat >> lapack_missing_temp.c << 'EOF'
#include <stdio.h>
/* Stub for complex Jacobi SVD - not implemented */
/* Note: f2c version returns int and may have extra string length parameters */
int cgejsv_(char* joba, char* jobu, char* jobv, char* jobr, char* jobt, char* jobp,
            int* m, int* n, void* a, int* lda, float* sva, void* u, int* ldu,
            void* v, int* ldv, void* cwork, int* lwork, float* work, int* lrwork,
            int* iwork, int* info,
            int joba_len, int jobu_len, int jobv_len, int jobr_len, int jobt_len, int jobp_len) {
    fprintf(stderr, "ERROR: cgejsv_ (complex Jacobi SVD) is not implemented in this build\n");
    *info = -999;  // Signal error
    return 0;
}
EOF
                ;;
        esac
    done
    
    # Compile the missing functions
    echo "Compiling missing LAPACK functions..."
    emcc -c lapack_missing_temp.c -o lapack_missing.o
    emar rcs liblapack_missing.a lapack_missing.o
    cp liblapack_missing.a "$PREFIX/lib/"
    
    # We'll add this to linker flags later after OCTAVE_LDFLAGS is set
    LAPACK_MISSING_LIB="-L$PREFIX/lib -llapack_missing"
    
    # Clean up
    rm -f lapack_missing_temp.c lapack_missing.o
    
    echo "Added missing LAPACK functions to liblapack_missing.a"
else
    echo "All critical LAPACK functions found in libclapack.a"
fi

# --- Note about SuiteSparse ---
echo "NOTE: SuiteSparse libraries are now included (sparse matrix functionality enabled)"
echo "The following libraries are available:"
echo "  - libcholmod.a, libumfpack.a, libamd.a, libcamd.a"
echo "  - libcolamd.a, libccolamd.a, libsuitesparseconfig.a"

# COMMENTED OUT: Previous SuiteSparse conversion attempt
# This didn't work because .so files (WebAssembly modules) can't be converted to .a files
# by simple copying - they have completely different formats.
#
# # Define the SuiteSparse libraries we tried to convert
# # SUITESPARSE_LIBS=(
# #     "amd:2.4.6"
# #     "camd:2.4.6"
# #     "colamd:2.9.6"
# #     "ccolamd:2.9.6"
# #     "cholmod:3.0.13"
# #     "umfpack:5.7.8"
# #     "suitesparseconfig:5.4.0"
# # )


# --- Phase 2: Environment and Metadata Setup ---

# Ensure pkg-config can find all dependencies in the environment
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"

# Set up CMAKE environment variables for cross-compiling to WASM
export CMAKE_PREFIX_PATH=$PREFIX
export CMAKE_SYSTEM_PREFIX_PATH=$PREFIX

# --- Fix Octave Package Metadata ---
# Our locally built octave package has two issues we need to fix:
# 1. The pkg-config files (.pc) contain hardcoded, non-relocatable paths.
# 2. They have malformed library paths that need correction.

echo "--- Fixing all Octave pkg-config files ---"

# Fix all octave-related .pc files (octave.pc, octinterp.pc, etc.)
for PC_FILE in $PREFIX/lib/pkgconfig/octave*.pc $PREFIX/lib/pkgconfig/octinterp*.pc; do
    if [ -f "$PC_FILE" ]; then
        echo "Fixing: $PC_FILE"
        
        # First, fix the hardcoded Docker build paths
        sed -i.bak "s|/usr/src/octave-wasm/target|${PREFIX}|g" "$PC_FILE"
        
        # Second, fix the library paths to use the "-l" linker flag
        # This tells the linker to search for the library in the -L paths
        # Handle both cases: with leading space and without
        sed -i "s| /liboctave/liboctave\.a| -loctave|g" "$PC_FILE"
        # sed -i "s|/liboctave/liboctave\.a| -loctave|g" "$PC_FILE"
        sed -i "s| /libinterp/liboctinterp\.a| -loctinterp|g" "$PC_FILE"
        # sed -i "s|/libinterp/liboctinterp\.a| -loctinterp|g" "$PC_FILE"
        
        # Show the patched content for verification
        echo "--- Contents of $PC_FILE after fixes ---"
        cat "$PC_FILE"
        echo "---"
    fi
done

# --- Get Full Static Linker Flags ---
# Now that the .pc files are fixed, we can use pkg-config to get the
# complete list of all static libraries required to link against Octave.
# The --static flag is critical here, as it resolves all private
# dependencies (like clapack, refblas, f2c, etc.).
# We need both octave and octinterp to get all required libraries.
echo "--- Getting all static linker flags from pkg-config ---"
RAW_OCTAVE_LDFLAGS=$(pkg-config --static --libs octave octinterp)
echo "Raw linker flags: ${RAW_OCTAVE_LDFLAGS}"

# No need to filter SuiteSparse libraries - they are now properly built as static libraries
echo "--- Using all libraries including SuiteSparse ---"
OCTAVE_LDFLAGS="$RAW_OCTAVE_LDFLAGS"

# Add -L$PREFIX/lib to ensure linker can find our extracted archives
OCTAVE_LDFLAGS="-L$PREFIX/lib $OCTAVE_LDFLAGS"

# Prepend missing LAPACK functions library if it was created
if [ -n "${LAPACK_MISSING_LIB:-}" ]; then
    OCTAVE_LDFLAGS="$LAPACK_MISSING_LIB -luuid $OCTAVE_LDFLAGS"
    echo "Added missing LAPACK functions to linker flags"
fi

# # Add C++ standard and ABI libraries at the end
# OCTAVE_LDFLAGS="$OCTAVE_LDFLAGS -lc++ -lc++abi"

export OCTAVE_LDFLAGS
echo "Filtered linker flags: ${OCTAVE_LDFLAGS}"
echo "------------------------------------------"

# --- Note: LAPACK functions workaround removed ---
# The octave-build-static package now includes all necessary LAPACK infrastructure
# functions (dlamch_, slamch_, ilaenv_, xerbla_, etc.) in libclapack.a, so the
# workaround is no longer needed.

# --- Configure and Build xeus-octave ---
# We pass the complete list of libraries to CMake, which will then
# correctly link them into the final xeus-octave.wasm kernel.

# Configure the build using emcmake
# Pass the full list of static libraries to the linker
emcmake cmake ${CMAKE_ARGS} \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_SYSTEM_NAME=Emscripten \
    -D CMAKE_EXE_LINKER_FLAGS="${OCTAVE_LDFLAGS}" \
    -D CMAKE_FIND_ROOT_PATH_MODE_PACKAGE=NEVER \
    -D XEUS_OCTAVE_BUILD_SHARED=OFF \
    -D XEUS_OCTAVE_BUILD_STATIC=ON \
    -D XEUS_OCTAVE_USE_SHARED_XEUS=OFF \
    -D XEUS_OCTAVE_DISABLE_ARCH_NATIVE=ON \
    -D CMAKE_INSTALL_PREFIX=$PREFIX \
    -D CMAKE_VERBOSE_MAKEFILE=ON \
    -D CMAKE_FIND_DEBUG_MODE=ON \
    -D ZLIB_INCLUDE_DIR=$PREFIX/include \
    -D ZLIB_LIBRARY=$PREFIX/lib/libz.a \
    -D PNG_PNG_INCLUDE_DIR=$PREFIX/include \
    -D PNG_LIBRARY=$PREFIX/lib/libpng.a \
    -S . -B build

# (Not sure if this is needed anymore)
# --- Move shared libraries after config and before build ---
# The cmake config step needs the .so files to exist to create the targets,
# but the build/link step will incorrectly use them. We move them now to
# ensure the static .a files are used during the final link.
echo "--- Moving shared libraries to force static linking ---"
if [ -f "$PREFIX/lib/libxeus.so" ]; then
    mv "$PREFIX/lib/libxeus.so" "$PREFIX/lib/libxeus.so.bak"
    echo "Moved libxeus.so to libxeus.so.bak"
fi
if [ -f "$PREFIX/lib/libxeus-lite.so" ]; then
    mv "$PREFIX/lib/libxeus-lite.so" "$PREFIX/lib/libxeus-lite.so.bak"
    echo "Moved libxeus-lite.so to libxeus-lite.so.bak"
fi

# Build with emmake
echo "--- Building xeus-octave ---"
emmake make -C build -j${CPU_COUNT}

# Install the built files
echo "--- Installing xeus-octave ---"
make -C build install

# --- Install kernel.json ---
# kernel's argv[0] is a bit wrong here. It needs to be `$PREFIX/bin/xoctave`
# We might also need to fix the `info/paths.json` inside of the archive. If you have issues, compare your output with https://github.com/baibhavbista/octave-xeus-lite/blob/6e76248b8add0e3851e70563e7294282f2d53e36/channels/local-channel/emscripten-wasm32/xeus-octave-wasm-0.2.0-h53eb3ed_4.tar.bz2
echo "--- Installing kernel.json ---"
KERNEL_INSTALL_DIR="$PREFIX/share/jupyter/kernels/xoctave"
mkdir -p "$KERNEL_INSTALL_DIR"
cp "$RECIPE_DIR/kernel.json" "$KERNEL_INSTALL_DIR/kernel.json"
echo "Installed kernel.json to $KERNEL_INSTALL_DIR"



# (like before, unsure if this is needed anymore)
# --- Restore shared libraries ---
echo "--- Restoring shared libraries ---"
if [ -f "$PREFIX/lib/libxeus.so.bak" ]; then
    mv "$PREFIX/lib/libxeus.so.bak" "$PREFIX/lib/libxeus.so"
    echo "Restored libxeus.so"
fi
if [ -f "$PREFIX/lib/libxeus-lite.so.bak" ]; then
    mv "$PREFIX/lib/libxeus-lite.so.bak" "$PREFIX/lib/libxeus-lite.so"
    echo "Restored libxeus-lite.so"
fi

echo "Build completed successfully!"