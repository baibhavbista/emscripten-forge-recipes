#!/bin/bash
set -ex

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
        sed -i "s| /liboctave/liboctave\.a| -loctave|g" "$PC_FILE"
        sed -i "s| /liboctinterp/liboctinterp\.a| -loctinterp|g" "$PC_FILE"
        
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
echo "--- Getting all static linker flags from pkg-config ---"
export OCTAVE_LDFLAGS=$(pkg-config --static --libs octave)
echo "Full linker flags: ${OCTAVE_LDFLAGS}"
echo "------------------------------------------"


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

# Build with emmake
echo "--- Building xeus-octave ---"
emmake make -C build -j${CPU_COUNT}

# Install the built files
echo "--- Installing xeus-octave ---"
make -C build install

echo "Build completed successfully!"