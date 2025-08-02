### **Project: `xeus-octave` WebAssembly Kernel Build Plan**

#### **1. High-Level Goal**

The primary objective is to compile the `xeus-octave` C++ project into a single, self-contained WebAssembly module (`xeus-octave.wasm`). This module will function as a GNU Octave kernel within a JupyterLite environment, enabling fully in-browser scientific computing.

#### **2. Core Challenge & Context**

The build process for `xeus-octave` is non-trivial because it depends on a complete, pre-compiled GNU Octave package. Our specific pre-compiled package (`octave-build-static`) was built in a separate Docker environment and has two key characteristics that must be addressed:

1.  **It is not a monolithic library:** The Octave package is composed of multiple, separate static libraries (e.g., `liboctave.a`, `libinterp.a`, `libclapack.a`, `librefblas.a`, `libf2c.a`, etc.). The final application must be linked against all of them correctly.
2.  **Its metadata contains hardcoded paths:** The package's `pkg-config` files (`.pc` files), which are meant to guide other build systems, contain absolute paths from the Docker container where it was built (e.g., `/usr/src/octave-wasm/target/...`). These paths are invalid in our current build environment, making the package non-relocatable by default.

#### **3. The Implemented Strategy**

Our strategy is to use the `xeus-octave` recipe's build script (`build.sh`) as an intelligent orchestrator. The script's main responsibility is to **repair the metadata** of the pre-built Octave package and then **use that repaired metadata** to correctly link all the disparate static libraries into the final `xeus-octave.wasm` binary.

This plan is executed in three phases within the `rattler-build` process.

---

#### **Phase 1: Dependency Declaration (`recipe.yaml`)**

*   **Objective:** To explicitly declare a dependency on our locally built, static Octave package.
*   **Implementation:** The `host` requirements in `recipes/recipes_emscripten/xeus-octave/recipe.yaml` are configured to depend on the exact name and version of our package (e.g., `octave-build-static == 0.1.0`). This ensures the build system uses our artifact. Dependencies that are now bundled within the Octave package (like `clapack`) are removed to prevent conflicts.

#### **Phase 2: Metadata Repair (`build.sh`)**

*   **Objective:** To find the Octave package's `pkg-config` files (`.pc`) and perform a series of `sed` commands to correct malformed paths and linker flags, making them usable in the current build environment.
*   **Implementation:**
    1.  The `build.sh` script first replaces the hardcoded absolute paths from the original Docker build environment with the correct `${PREFIX}` variable.
    2.  It then corrects malformed library paths (e.g., `/liboctave/liboctave.a`) by converting them into the proper linker-friendly flags (e.g., `-loctave`). This ensures the linker can find the libraries in the search paths provided by the `-L` flags.

#### **Phase 2.5: SuiteSparse Library Conversion (`build.sh`)**

*   **Objective:** To convert SuiteSparse shared libraries (`.so` files) to static libraries (`.a` files) that are required for WebAssembly linking.
*   **Core Problem:** The `octave-build-static` package was built incorrectly. Instead of creating static libraries for SuiteSparse components (cholmod, umfpack, etc.), it created shared libraries (`.so` files). Additionally, the main Octave archives (`liboctave.a`, `liboctinterp.a`) are malformed with corrupted member names. The WebAssembly linker requires static libraries and cannot use the `.so` files directly.
*   **Root Cause:** The SuiteSparse build process in the `octave-build-static` Dockerfile didn't properly create static libraries despite using the `static` target, likely due to incompatibilities between the SuiteSparse Makefile and Emscripten's build system.
*   **Implementation (Library Format Conversion):**
    1.  The `build.sh` script identifies all SuiteSparse `.so` files in the package (libcholmod.so, libumfpack.so, libamd.so, etc.).
    2.  For each `.so` file, it extracts the WebAssembly object code using `wasm-objcopy` or similar tools.
    3.  It then uses `emar` (Emscripten's archive tool) to create proper static library archives (`.a` files) from the extracted objects.
    4.  These newly created `.a` files are placed in `$PREFIX/lib/` where the build system expects to find them.
    5.  The malformed Octave archives are left as-is since they still contain valid object files, just with unusual member names.

#### **Phase 3: Static Library Resolution and Linking (`build.sh` and `CMakeLists.txt`)**

*   **Objective:** To provide the `xeus-octave` CMake build system with the complete and correct set of include paths and linker flags needed to build the final `.wasm` module.
*   **Implementation:**
    1.  With the `.pc` files and the static libraries now fully repaired, `build.sh` calls `pkg-config --static --libs octave` to get the complete, correct linker flag string and stores it in the `OCTAVE_LDFLAGS` environment variable.
    2.  The `CMakeLists.txt` file (modified via a patch) is configured to find the Octave include paths using `pkg_check_modules` and adds them to the compiler flags.
    3.  Crucially, the `CMakeLists.txt` is also modified to *not* perform its own linking for Octave, ensuring no conflicts.
    4.  Finally, the `OCTAVE_LDFLAGS` variable is passed directly to the `emcmake` command via the `CMAKE_EXE_LINKER_FLAGS` directive. This provides the linker with the exact, complete, and correct set of libraries it needs to perform the final linking operation.

#### **4. Current Status & Revised Approach**

**Critical Discoveries:**
1. The `octave-build-static` package has fundamental structural issues:
   - SuiteSparse libraries exist only as `.so` files (WebAssembly modules), not proper `.a` (static archive) files
   - The main Octave archives (`liboctave.a`, `liboctinterp.a`) contain embedded archives (`libclapack.a`, `librefblas.a`, `libf2c.a`)
   - Simply copying `.so` to `.a` doesn't work - they have completely different formats

2. Root cause analysis of the Dockerfile confirms:
   - SuiteSparse `make static` command doesn't work properly with Emscripten
   - Octave's build system embedded BLAS/LAPACK/F2C archives inside its own archives

**Revised Immediate Approach: Skip SuiteSparse**
Since converting `.so` to `.a` is not feasible, we'll attempt to build without SuiteSparse:

1. **Extract embedded archives**: Pull out the valid `libclapack.a`, `librefblas.a`, and `libf2c.a` from within the Octave archives
2. **Rebuild clean Octave archives**: Create new `liboctave.a` and `liboctinterp.a` containing only object files
3. **Skip SuiteSparse linking**: Remove `-lcholmod`, `-lumfpack`, etc. from linker flags
4. **Add library search path**: Include `-L$PREFIX/lib` to find extracted archives

This approach will likely disable sparse matrix functionality but may allow basic Octave operations to work.

#### **5. Backup Plan: Fix the Dockerfile**

If skipping SuiteSparse fails (due to hard dependencies), we must fix the root cause:

**Dockerfile modifications needed:**
1. **Fix SuiteSparse static library generation**:
   ```dockerfile
   # Instead of relying on 'make static', explicitly create archives:
   RUN cd $THIRDPARTYDIR/suitesparse-5.4.0 && \
       # Build object files
       emmake make ... && \
       # Manually create static archives from .o files
       find AMD -name "*.o" -exec emar cr $LIBDIR/libamd.a {} + && \
       find UMFPACK -name "*.o" -exec emar cr $LIBDIR/libumfpack.a {} + && \
       # ... repeat for other components
   ```

2. **Prevent archive-within-archive issue**:
   - Investigate Octave's use of libtool
   - Possibly add `--disable-libtool-lock` or similar flags
   - Post-process archives to extract embedded dependencies

**Expected outcomes:**
- Properly structured `octave-build-static` package with all dependencies as separate `.a` files
- Clean linking process without workarounds in `xeus-octave`

**Timeline:**
- Try the skip-SuiteSparse approach first (quick fix)
- If that fails, implement the Dockerfile fix (proper solution) 