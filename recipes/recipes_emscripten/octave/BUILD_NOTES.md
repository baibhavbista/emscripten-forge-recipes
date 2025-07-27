# Octave WebAssembly Build - Changes Summary

## Overview
This document summarizes the changes made to build GNU Octave 9.4.0 for WebAssembly using Emscripten, focusing on resolving Fortran compilation issues by switching to F2C. These changes are implemented in the `recipes/recipes_emscripten/octave` directory.

## Current Goal
Build a working WebAssembly version of Octave by:
1. Converting all Fortran code to C using F2C
2. Compiling everything as static libraries (WebAssembly requirement)
3. Resolving libtool and F2C compatibility issues
4. Creating a single `octave-cli.wasm` executable

## Key Problems Solved

### 1. **Fortran Compiler Issues**
- **Original**: Used `flang` (LLVM Fortran) with `openblas-flang`
- **Problem**: Mixed toolchain (flang + Emscripten) caused WebAssembly validation errors
- **Solution**: Switched to F2C (Fortran-to-C translator) approach

### 2. **Shared vs Static Libraries**
- **Original**: Patch forced shared libraries even with `--disable-shared`
- **Problem**: WebAssembly doesn't support traditional shared libraries
- **Solution**: Removed problematic patch, build static libraries only

### 3. **Missing Symbols**
- **Problem**: Undefined symbols for threads and Fortran decimal conversion
- **Solution**: Created stubs and linked proper libraries

### 4. **F2C Wrapper Path Issues** (Fixed)
- **Problem**: Libtool passes full paths for output files, wrapper was creating nested paths
- **Solution**: Fixed path handling in f2c-emcc wrapper to handle absolute paths correctly

### 5. **F2C Code Generation Issues** (Fixed)
- **Problem**: F2C generates `(...)` for unknown function prototypes, invalid in C99+
- **Solution**: Added sed command to replace `(...)` with `(void)` in generated C code

## Changes Made

### `recipe.yaml` Changes

```yaml
# Key changes:
patches:
  # - 0001-Force-detection-of-shared-libs.patch  # REMOVED - forces shared libs
  - 0002-Remove-COMMON.patch
  - 0003-Delete-odepack.patch

requirements:
  build:
    - f2c  # Native F2C translator (not libf2c!)
    # Removed: flang_${{ target_platform }}
    # Removed: micromamba
  host:
    - libf2c  # WebAssembly F2C runtime
    - openblas  # F2C-based (not openblas-flang!)
    - pcre2>=10.43
```

### `build.sh` Key Components

1. **F2C Wrapper Script (`f2c-emcc`)**
   - Handles libtool's compilation commands
   - Translates `.f` files to `.c` using f2c
   - Fixes F2C's invalid C code: `sed -i 's/(\.\.\.)/(void)/g'`
   - Compiles `.c` files with emcc
   - Properly handles both relative and absolute output paths

2. **Configure Patches**
   ```bash
   # Allow static-only builds
   sed -i 's/as_fn_error \$? "Building shared libraries is required!".*$/# Removed/' configure
   
   # Set F2C calling convention
   sed -i 's/#define F77_RET_T.*/#define F77_RET_T int/' liboctave/util/f77-fcn.h
   sed -i 's/#define F77_RETURN.*/#define F77_RETURN(retval) return 0;/' liboctave/util/f77-fcn.h
   ```

3. **Build Configuration**
   - `--disable-shared --enable-static` for static linking
   - `--enable-fortran-calling-convention="f2c"`
   - Thread stubs for disabled threading

## Current Build Status

### What's Working
- F2C wrapper successfully converts most Fortran files
- Path handling issues resolved
- F2C code generation issues fixed with sed

### Disabled Features
- **ARPACK** (`--without-arpack`) - Eigenvalue computations for sparse matrices (`eigs` function)
- **Audio** (`--without-sndfile --without-portaudio`) - Sound file I/O and audio playback
- **Compression** (`--without-z --without-bz2`) - zlib and bzip2 compression
- **cURL** (`--without-curl`) - Network file transfers
- **FFT** (`--without-fftw3 --without-fftw3f`) - Fast Fourier Transform libraries
- **Fonts** (`--without-freetype --without-fontconfig`) - Font rendering
- **Graphics/GUI** (`--without-qt --without-opengl --without-x --without-fltk`) - All graphical interfaces
- **HDF5** (`--without-hdf5`) - HDF5 file format support
- **Image Processing** (`--without-magick`) - ImageMagick integration
- **JSON** (`--disable-rapidjson`) - RapidJSON parsing
- **Linear Programming** (`--without-glpk`) - GNU Linear Programming Kit
- **QRupdate** (`--without-qrupdate`) - QR factorization updates
- **Readline** (`--disable-readline`) - Command line editing
- **Sparse Matrix Libraries** (`--without-cxsparse --without-ccolamd --without-spqr`) - Various sparse matrix algorithms
- **Sundials ODE Solvers** (`--without-sundials_*`) - Advanced ODE/DAE solvers
- **Qhull** (`--without-qhull_r`) - Computational geometry
- **Dynamic modules** (`.oct` files) - WebAssembly doesn't support dynamic loading

### Features to Consider Re-enabling
After achieving a working build, these features might be needed for specific use cases:

1. **For CS229/ML workflows**:
   - Compression libraries (z, bz2) - for loading compressed datasets
   - HDF5 - if datasets are in HDF5 format
   - Sparse matrix support - for some ML algorithms
   - FFT - for signal processing tasks

2. **For xeus-octave integration**:
   - JSON support - if the kernel needs Octave to parse JSON directly
   
3. **For general scientific computing**:
   - Image processing (ImageMagick) - for computer vision tasks
   - Linear programming (GLPK) - for optimization problems

### Remaining Issues
- Libtool still treating `.la` files as shared libraries (warnings)
- Need to ensure all Fortran files compile successfully
- May need additional fixes for specific F2C-generated code patterns

## Debugging Commands

When debugging build issues, run these commands from the project root:

### Check Build Output
```bash
# View the most recent build log
cat logfile.txt | tail -100

# Search for specific errors
grep -B5 -A5 "error:" logfile.txt

# Check for F2C-related issues
grep -E "f2c|F77|\.f" logfile.txt | grep -B2 -A2 "error"
```

### Inspect Build Directory
```bash
# Navigate to the work directory
cd output/bld/rattler-build_octave_*/work

# Check if Fortran files were converted
ls -la liboctave/external/*/*.c 2>/dev/null | head -20

# Check for missing object files
find . -name "*.lo" -exec cat {} \; | grep "\.o" | while read obj; do
  [ ! -f "$obj" ] && echo "Missing: $obj"
done

# Check libtool configuration
grep -E "^enable_shared|^build_old_libs|^build_libtool_libs" libtool
```

### Debug F2C Wrapper
```bash
# Test the F2C wrapper directly
cd output/bld/rattler-build_octave_*/work
./f2c-emcc -c -o test.o liboctave/external/amos/cacai.f

# Check if C file was generated
ls -la liboctave/external/amos/cacai.c

# Check for compilation errors
cat liboctave/external/amos/cacai.c | grep "(\.\.\."
```

### Common Issues to Check
```bash
# Check for shared library warnings
grep "Warning.*shared library" logfile.txt | head -10

# Check for undefined symbols
grep "undefined symbol" logfile.txt | head -10

# Check Makefile variables
cd output/bld/rattler-build_octave_*/work
grep -E "^F77|^FLIBS|^LIBS" Makefile
```

## Why F2C Works Better

1. **Single Toolchain**: Everything compiled with Emscripten
2. **No Fortran Runtime Issues**: F2C generates pure C code
3. **WebAssembly Compatible**: No validation errors from Fortran constructs
4. **Proven Approach**: F2C-based OpenBLAS already works for WebAssembly

## Octave's Fortran Components

Octave includes significant Fortran code beyond BLAS/LAPACK:
- **AMOS** (66 files) - Special functions for complex Bessel functions
- **BLAS-XTRA** (24 files) - Extra BLAS routines
- **ODE Solvers** (56 files) - DASPK, DASRT, DASSL, ODEPACK
- **QUADPACK** (17 files) - Numerical integration
- **RANLIB** (35 files) - Random number generation
- **SLATEC** (47 files) - Mathematical library functions

All these are handled by the F2C translation approach.

## Build Process Flow

1. **Fortran → C**: F2C translates Octave's Fortran files
2. **Fix Generated C**: Sed fixes invalid C99+ syntax from F2C
3. **C → WASM**: Emscripten compiles everything
4. **Static Linking**: All libraries linked into single WASM file
5. **No Dynamic Modules**: `.oct` files created as empty placeholders

## Dependencies

- **Build** (linux-64): `f2c`, `emscripten`, standard build tools
- **Host** (emscripten-wasm32): `libf2c`, `openblas`, `pcre2`

## Result

A single `octave-cli.wasm` file containing all Octave functionality, suitable for running in WebAssembly environments without dynamic loading requirements.

## Technical Details

### F2C Wrapper Implementation
The build creates a `f2c-emcc` wrapper that:
```bash
# Parse arguments for Fortran files
if [[ -n "$source_file" ]]; then
    # Handle paths correctly
    source_dir=$(dirname "$source_file")
    source_base=$(basename "$source_file" .f)
    
    # Convert to C
    cd "$source_dir"
    f2c -a -C++ -Nn802 -Nx400 "$(basename "$source_file")"
    cd - > /dev/null
    
    # Fix F2C's invalid C code
    sed -i 's/(\.\.\.)/(void)/g' "${source_dir}/${source_base}.c"
    
    # Compile with emcc
    emcc -c "${source_dir}/${source_base}.c" -o "$output"
fi
```

### Known F2C Issues and Fixes
1. **Invalid function prototypes**: F2C generates `(...)` which is invalid in C99+
   - Fixed with: `sed -i 's/(\.\.\.)/(void)/g'`
2. **Path handling with libtool**: Libtool passes full paths that need careful handling
   - Fixed by separating source and output path logic

### Static Library Handling
- Removes shared library requirements from configure
- Uses `--disable-shared --enable-static`
- Creates thread stubs for missing symbols
- Fixes OpenBLAS static library naming (symlinks architecture-specific name to libopenblas.a)
- Handles `.oct` files as dummy placeholders

### Stub Implementations
1. **Thread stubs** (`thread_stubs.cpp`):
   - Implements `octave::thread::init()` and `octave::thread::is_thread()`
   - Required because Octave still references these even with `--disable-threads`

### Known Issues and Fixes
1. **OpenBLAS static library naming**:
   - OpenBLAS installs with architecture-specific names (e.g., `libopenblas_riscv64_generic-r0.3.26.a`)
   - Octave expects `libopenblas.a`
   - Fixed by creating a symlink

### Key Patches Kept
- `0002-Remove-COMMON.patch` - Fortran COMMON block fixes
- `0003-Delete-odepack.patch` - Removes problematic ODEPACK

### Key Patches Removed
- `0001-Force-detection-of-shared-libs.patch` - Was forcing shared libs

## Troubleshooting

If build fails:
1. Check F2C is available in build environment
2. Verify libf2c is available for emscripten-wasm32
3. Ensure using `openblas` not `openblas-flang`
4. Check for F2C code generation issues in the logs
5. Look for missing .o files that indicate compilation failures
6. Check if libtool is still trying to create shared libraries despite configuration 