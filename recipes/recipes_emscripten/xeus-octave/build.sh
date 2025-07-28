#!/bin/bash
set -ex

# Ensure pkg-config can find all dependencies in the environment
export PKG_CONFIG_PATH="${PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"

# --- Fix Octave Package Metadata ---
# Our locally built octave package has two issues we need to fix:
# 1. The pkg-config file (.pc) contains hardcoded, non-relocatable paths.
# 2. It doesn't explicitly list all the static libraries needed for linking.

# Find the main pkg-config file provided by the octave package.
# The exact path might vary slightly, so we search for it.
OCTAVE_PC_FILE=$(find $PREFIX -name "octave.pc")
if [ -z "$OCTAVE_PC_FILE" ]; then
    echo "Error: Could not find octave.pc in $PREFIX"
    exit 1
fi

echo "--- Found pkg-config file at: ${OCTAVE_PC_FILE} ---"

# Fix the hardcoded paths by replacing the build-time prefix
# with the actual prefix of our current build environment.
echo "--- Fixing hardcoded paths in pkg-config file ---"
sed -i.bak "s|/usr/src/octave-wasm/target|${PREFIX}|g" "${OCTAVE_PC_FILE}"

echo "--- Patched ${OCTAVE_PC_FILE} contents: ---"
cat "${OCTAVE_PC_FILE}"
echo "------------------------------------------"

# --- Get Full Static Linker Flags ---
# Now that the .pc file is fixed, we can use pkg-config to get the
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
emcmake cmake ${CMAKE_ARGS} \
    -D CMAKE_BUILD_TYPE=Release \
    -D CMAKE_SYSTEM_NAME=Emscripten \
    # Pass the full list of static libraries to the linker
    -D CMAKE_EXE_LINKER_FLAGS="${OCTAVE_LDFLAGS}" \
    -D XEUS_OCTAVE_BUILD_SHARED=OFF \
    -D XEUS_OCTAVE_BUILD_STATIC=ON \
    -D XEUS_OCTAVE_USE_SHARED_XEUS=OFF \
    -D XEUS_OCTAVE_DISABLE_ARCH_NATIVE=ON \
    -D CMAKE_INSTALL_PREFIX=$PREFIX \
    -D CMAKE_VERBOSE_MAKEFILE=ON \
    -S . -B build

# Build with emmake
echo "--- Building xeus-octave ---"
emmake make -C build -j${CPU_COUNT}

# Install the built files
echo "--- Installing xeus-octave ---"
make -C build install

echo "Build completed successfully!"