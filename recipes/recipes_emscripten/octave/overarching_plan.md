Project Goal: Create a fully browser-based Jupyter notebook for GNU Octave by compiling the interpreter to WebAssembly and integrating it with JupyterLite via a Xeus kernel.

Phase 1: Environment Setup and Baseline Build
Goal: To establish a working build environment and get the first set of compiler errors from the emscripten-forge recipe. This phase is about preparation, not success.

1.1: Set Up mamba and Emscripten

[ ] Install mamba (or conda). mamba is recommended for its speed in resolving complex dependencies.

[ ] Create a new, isolated environment for this project (e.g., mamba create -n octave-wasm-dev).

[ ] Activate the environment (mamba activate octave-wasm-dev).

[ ] Follow the emscripten-forge documentation to install the Emscripten SDK and configure your environment.

1.2: Clone the emscripten-forge Recipes

[ ] Clone the emscripten-forge/recipes repository: git clone https://github.com/emscripten-forge/recipes.git.

[ ] cd into the recipes directory.

[ ] Find and check out the specific pull request or branch containing the Octave recipe you found (pull/2196).

1.3: Attempt the First Build

[ ] Navigate to the Octave recipe directory within the cloned repository.

[ ] Run the build command, e.g., `rattler-build build --recipe recipes/recipes_emscripten/octave --target-platform emscripten-wasm32`.

[ ] Expect this build to fail. The objective is to capture the initial log of compiler errors. Save this log to a file for analysis.

✅ Success Metric: You have a working build environment and a log file of the first compilation errors.

Phase 2: Porting Octave (The Core Task)
Goal: To iteratively fix build errors and create a set of modern patches, resulting in a compiled and packaged Octave WASM library.

2.1: Establish the Debugging Loop

[ ] Analyze: Pick the first error from your build log (e.g., error: 'fork' is not available on this platform).

[ ] Consult: Search rwl/octave-4.4.1 to see how he addressed this specific function or area. Note why he made the change (e.g., "disabling process management as it's unavailable in the browser").

[ ] Implement: In the modern Octave source code used by the recipe, implement a fix. This usually involves wrapping the problematic code in an #ifdef __EMSCRIPTEN__ block to disable it or provide a browser-compatible stub function.

[ ] Rebuild: Run the build command again to confirm the fix and reveal the next error. Repeat this loop.

2.2: Systematically Address Key Problem Areas

[ ] Fortran Code: Octave has extensive Fortran dependencies (BLAS, LAPACK, ODE solvers, etc.)
   - Consider using F2C (Fortran-to-C translator) instead of a Fortran compiler
   - Create an f2c wrapper script that translates .f files to .c before compilation
   - Fix F2C-generated code issues (e.g., `(...)` → `(void)` for C99 compliance)

[ ] Build System: Octave's autotools expect to build shared libraries
   - Remove patches that force shared libraries (e.g., `0001-Force-detection-of-shared-libs.patch`)
   - Configure with `--disable-shared --enable-static`
   - Patch configure script to remove shared library requirements
   - Handle libtool issues with static-only builds

[ ] Dependency Management: Aggressively disable all non-essential features
   - Start with maximum --without flags to avoid linking errors
   - This includes: ARPACK, cURL, FFT, HDF5, graphics, audio, compression, etc.
   - Get a minimal build working first
   - Selectively re-enable features only as needed for specific use cases
   - Watch for static vs shared library issues (WebAssembly needs static)
   - OpenBLAS may install with architecture-specific names - create symlinks as needed

[ ] Process Management: Disable functions like fork, exec, system.

[ ] Threading: WebAssembly has limited threading support
   - Configure with `--disable-threads`
   - Create stub functions for any remaining thread symbols

[ ] Filesystem I/O: Replace or disable direct POSIX I/O calls where possible, relying on Emscripten's virtual filesystem (FS object).

[ ] Networking: Disable any networking code (e.g., dependencies on libcurl).

[ ] GUI/Plotting: Initially, disable all GUI toolkits (Qt, FLTK). Plotting will be a separate, later challenge.

[ ] Dynamic Linking: Stub out or disable dlopen, dlsym as they have limited support in Emscripten.
   - Octave's .oct files (dynamic modules) won't work - create empty placeholder files

✅ Success Metric: The emscripten-forge recipe completes successfully, producing a packaged octave library for the emscripten-wasm32 platform in your local mamba channel.

Phase 3: Kernel Integration with xeus-octave
Goal: To compile xeus-octave to WASM, linking it against the Octave library you just created.

3.1: Set up a Kernel Project

[ ] Create a new directory for your kernel build.

[ ] Use the build setup from a jupyterlite-xeus demo as a template. You'll need a top-level CMakeLists.txt file configured for the Emscripten toolchain.

3.2: Link Dependencies in CMake

[ ] Configure your CMakeLists.txt to find and link against the xeus and xtl libraries from emscripten-forge.

[ ] Configure CMake to find and link against your locally-built octave package. This involves pointing it to the correct headers and the compiled WASM library file.

[ ] Ensure all Fortran dependencies are properly linked (libf2c if using F2C approach).

3.3: Compile the Kernel

[ ] Run the Emscripten-aware CMake and make commands (e.g., emcmake cmake .. and emmake make).

[ ] Debug any new compilation issues. These are often related to C++ features or minor incompatibilities.

[ ] Watch for WebAssembly validation errors - may need to bypass wasm-opt if issues persist.

✅ Success Metric: You have a single xeus-octave.wasm file containing the kernel logic and the entire Octave interpreter.

Phase 4: Deploy with JupyterLite
Goal: To package your WASM kernel into a functional, browser-based Jupyter notebook application.

4.1: Prepare the JupyterLite Site

[ ] Clone your xeus-octave-lite-demo repository or set up a new one.

[ ] Copy your xeus-octave.wasm file and any other necessary runtime files (like .js loaders) into the project.

4.2: Configure the JupyterLite Kernel

[ ] Modify the jupyter-lite.json file to register your kernel. Define its display name (Octave), language (octave), and the path to the WASM file.

[ ] Ensure the JavaScript loader file correctly initializes the Emscripten module and the kernel.

[ ] Set up virtual filesystem with any required data files.

4.3: Build and Launch

[ ] Install the JupyterLite CLI: pip install jupyterlite.

[ ] Run jupyter lite build to package the site.

[ ] Serve the generated dist (or _output) folder with a local web server to test it.

✅ Success Metric: You can open a webpage, start a new notebook, see an "Octave" kernel option that successfully starts, and run a simple command like a = 5; disp(a).

Phase 5: Validation and Refinement
Goal: To test the notebook against a real-world use case, fix bugs, and refine the user experience.

5.1: Deploy for Testing

[ ] Push your built JupyterLite site to a static hosting service like GitHub Pages for easy access and sharing.

5.2: Run the CS229 Exercises

[ ] Systematically go through the Octave/MATLAB code from Andrew Ng's course exercises.

[ ] Run the code cell-by-cell.

[ ] Create a log of what works and what doesn't. Pay special attention to:

Matrix operations (*, inv, pinv)

Loading data (this will require pre-loading files into the virtual filesystem)

Plotting functions (plot, imagesc)

5.3: Iterate and Fix

[ ] For bugs in core Octave functions, go back to Phase 2 to patch and rebuild.

[ ] For issues with plotting, investigate how to pipe Octave's graphics output (e.g., from gnuplot) to an HTML canvas. This is a common advanced challenge for WASM ports.

[ ] For performance issues, profile and optimize critical paths (matrix operations should be fast with BLAS).

[ ] Rebuild the kernel (Phase 3), redeploy the site (Phase 4), and re-test.

✅ Success Metric: The majority of the non-GUI code from the CS229 exercises runs correctly. You have a working, shareable demo of an in-browser Octave notebook.

## Key Lessons Learned

1. **Fortran is a major challenge** - Using F2C simplifies the toolchain significantly
2. **Build system assumptions** - Many autotools projects assume shared libraries; extensive patching may be needed
3. **Static library naming** - Dependencies may install with non-standard names (e.g., OpenBLAS with architecture suffixes)
4. **Incremental progress is key** - Each fixed error reveals the next challenge
5. **Document everything** - Keep detailed notes (like BUILD_NOTES.md) for future reference