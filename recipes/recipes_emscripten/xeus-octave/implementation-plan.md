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

*   **Objective:** To find the Octave package's `pkg-config` files after they have been installed into the build environment and fix their hardcoded, non-relocatable paths.
*   **Implementation:**
    1.  The `build.sh` script begins by searching the build environment (`$PREFIX`) for the main `octave.pc` file.
    2.  It then executes a `sed -i` command to perform an in-place search and replace on the file. This command replaces the hardcoded path from the Docker build (e.g., `/usr/src/octave-wasm/target`) with the `${PREFIX}` variable, which represents the correct, current installation path. This makes the metadata file valid and relocatable.

#### **Phase 3: Static Library Resolution and Linking (`build.sh`)**

*   **Objective:** To combine the `xeus-octave` object files with the *entire collection* of Octave's static libraries into a single, final `.wasm` module.
*   **Implementation:**
    1.  With the `octave.pc` file now repaired, the script uses the `pkg-config` command-line tool to read it.
    2.  Crucially, it calls `pkg-config --static --libs octave`. The `--static` flag instructs `pkg-config` to resolve the *entire dependency tree*, including all "private" libraries listed in the `Libs.private` field of the `.pc` file.
    3.  The output of this command is a single, long string containing the correct linker flags for *every required static library* (e.g., `-L/path/to/libs /path/to/liboctave.a /path/to/libclapack.a ...`).
    4.  This complete set of linker flags is stored in an environment variable (`OCTAVE_LDFLAGS`).
    5.  Finally, this variable is passed to the `xeus-octave` `CMake` build system via the `CMAKE_EXE_LINKER_FLAGS` directive. This provides CMake with all the information it needs to perform the final, complex linking operation, resulting in a correctly built and self-contained `xeus-octave.wasm` file. 