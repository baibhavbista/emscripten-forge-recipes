# Phase 3 Detailed Plan: Building the `xeus-octave` WASM Kernel

This plan involves creating a new recipe that will orchestrate the cross-compilation of `xeus-octave` to WebAssembly. The goal of this phase is to compile the `xeus-octave` C++ project into a single WebAssembly module (`.wasm`) by linking it against the `xeus`, `xtl`, and our newly created `octave` libraries.

---

### **Step 1: Scaffolding the `xeus-octave` Recipe**

The first step is to create the necessary directory structure and files for our new build recipe.

*   **Action:** Create a new directory: `recipes/recipes_emscripten/xeus-octave/`.
*   **Action:** Inside this new directory, create two initial empty files:
    *   `recipe.yaml`
    *   `build.sh`

### **Step 2: Defining the Build in `recipe.yaml`**

We will configure the `recipe.yaml` file to define the source code, dependencies, and metadata for the `xeus-octave` package.

*   **Action: Define the Source**
    *   The recipe will pull the source code directly from the official `xeus-octave` GitHub repository. We will pin it to a specific git tag to ensure the build is reproducible.
*   **Action: Define Build-Time Dependencies**
    *   These are the tools needed on the build machine. We will specify standard tools like `cmake`, `make`, and the `emscripten` C++ compiler (`emcc`).
*   **Action: Define Host-Time Dependencies (The WASM Libraries)**
    *   This is the most critical part. We will declare the `emscripten-wasm32` libraries that `xeus-octave` needs to link against:
        1.  **`octave`**: Your `octave-9.4.0-pl5321h658c483_0.tar.bz2` package. The build system will automatically find and use it.
        2.  **`xeus`**: The core Jupyter protocol library.
        3.  **`xtl`**: The C++ utility library used by Xeus.
        4.  Other dependencies like `zeromq`, `nlohmann_json`, and `openssl`.

### **Step 3: Scripting the Build in `build.sh`**

This script will contain the commands to configure, compile, and install `xeus-octave`. The process will be similar to the Octave build, using Emscripten's toolchain wrappers.

*   **Action: Configure with `emconfigure` and `cmake`**
    *   The script will call `cmake` via `emconfigure`, which automatically sets up the Emscripten toolchain for cross-compilation.
    *   We will pass essential flags to `cmake`:
        *   `--disable-shared --enable-static`: Force a static build, which is required for a single `.wasm` file.
        *   We will inspect the `xeus-octave/CMakeLists.txt` and disable any features that are not applicable to a browser environment (e.g., native-only examples or tests).
*   **Action: Compile with `emmake` and `make`**
    *   After a successful configuration, the script will run `make` (via `emmake`) to compile the C++ source code into WebAssembly object files and link them against the static libraries from our dependencies.

### **Step 4: The Iterative Patching Loop (The Core Work)**

The `xeus-octave` project was not originally designed to be compiled for WebAssembly. The first build attempt will fail. We will then enter an iterative cycle of fixing issues.

*   **Process:**
    1.  **Run the Build:** Execute the first build attempt.
    2.  **Analyze Errors:** The build will fail with either a `cmake` configuration error or a C++ compilation error. I will analyze the log to pinpoint the cause (e.g., an OS-specific function call, an incorrect library path, etc.).
    3.  **Create a Patch:** I will create a small `.patch` file that modifies the `xeus-octave` source code to fix the specific error.
    4.  **Update `recipe.yaml`:** I will add the new patch file to the `patches` section of the `recipe.yaml`.
    5.  **Repeat:** I will re-run the build, which will now apply the patch and proceed until it hits the next issue.

This loop will be repeated until all compilation and linking errors are resolved.

### **Step 5: Verification**

The final output of a successful build will be a new conda package, `xeus-octave-wasm.tar.bz2` (the name will be refined).

*   **Success Metric:** This package will contain the final, self-contained `xeus-octave.wasm` module and its accompanying JavaScript loader. This artifact is the primary goal of this phase and the direct input for **Phase 4: Deploy with JupyterLite**. 