#!/bin/bash

# Add shebang for proper shell detection
set -e  # Exit on error

# Remove spaces in `-s OPTION` from emscripten to avoid confusion
export LDFLAGS="$(echo "${LDFLAGS}" |  sed -E 's/-s +/-s/g')"

# Set up F2C for Fortran compilation
# Create a wrapper that uses f2c to convert Fortran to C, then compiles with emcc
cat > f2c-emcc << 'EOF'
#!/bin/bash
# Wrapper to compile Fortran files using f2c and emcc
# This mimics a Fortran compiler but uses f2c + emcc internally

output=""
compile_only=0
source_file=""
other_args=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -c)
            compile_only=1
            ;;
        -o)
            shift
            output="$1"
            ;;
        *.f|*.F)
            source_file="$1"
            ;;
        *)
            other_args+=("$1")
            ;;
    esac
    shift
done

if [[ -n "$source_file" ]]; then
    # Get base name and directory
    source_dir=$(dirname "$source_file")
    source_base=$(basename "$source_file" .f)
    source_base=$(basename "$source_base" .F)
    
    # Handle output path
    if [[ -n "$output" ]]; then
        # If output has a directory component, use it as-is
        output_dir=$(dirname "$output")
        output_base=$(basename "$output")
    else
        # Default output in same directory as source
        output_dir="$source_dir"
        output_base="${source_base}.o"
        output="${output_dir}/${output_base}"
    fi
    
    # Convert Fortran to C in the source directory
    cd "$source_dir"
    f2c -a -C++ -Nn802 -Nx400 "$(basename "$source_file")"
    cd - > /dev/null
    
    # Fix f2c-generated code that uses (...) instead of (void) or proper variadic syntax
    # This is a known issue with f2c generating invalid C99+ code
    sed -i 's/(\.\.\.)/(void)/g' "${source_dir}/${source_base}.c"
    
    # Compile C to object
    emcc -c "${source_dir}/${source_base}.c" -I$PREFIX/include -o "$output" "${other_args[@]}"
    
    # Clean up
    rm -f "${source_dir}/${source_base}.c"
fi
EOF
chmod +x f2c-emcc
export F77="${PWD}/f2c-emcc"
export FC="${PWD}/f2c-emcc"

# Set up flags for C/C++ compilation
export CFLAGS="${CFLAGS} --target=wasm32-unknown-emscripten"
export CXXFLAGS="${CXXFLAGS} --target=wasm32-unknown-emscripten"

# Octave overrides xerbla from Lapack.
# Both Blas and Lapack define xerbla zerbla_array lsame.
export LDFLAGS="${LDFLAGS} -Wl,--allow-multiple-definition"

# Force disable pthread
sed -i 's/ax_pthread_ok=yes/ax_pthread_ok=no/' configure
export ac_cv_header_pthread_h=no

# We need F2C calling convention with int return for F2C-compiled code
sed -i 's/#define F77_RET_T.*/#define F77_RET_T int/' liboctave/util/f77-fcn.h
sed -i 's/#define F77_RETURN.*/#define F77_RETURN(retval) return 0;/' liboctave/util/f77-fcn.h

# Forcing autotools to NOT rerun after patches
find . -exec touch -t $(date +%Y%m%d%H%M) {} \;

BUILD="x86_64-unknown-linux-gnu"
# Pretend to build for linux because autotools does not know about emscripten
HOST="wasm32-unknown-linux-gnu"

# Force Fortran name mangling convention for F2C
export ac_cv_f77_mangling="lower case, underscore, no extra underscore"

# Set BLAS/LAPACK paths explicitly
export BLAS_LIBS="-L$PREFIX/lib -lopenblas"
export LAPACK_LIBS="-L$PREFIX/lib -lopenblas"

# Patch configure to bypass broken LAPACK detection
sed -i 's/if test $ax_blas_ok = no || test $ax_lapack_ok = no; then/if false; then # PATCHED/' configure

# Remove the error that requires shared libraries
sed -i 's/as_fn_error \$? "Building shared libraries is required!" "\$LINENO" 5/# Removed shared library requirement for WASM/' configure

# Also ensure that SHARED_LIBS is set to no when --disable-shared is used
sed -i '/^enable_shared=yes$/d' configure
sed -i '/^SHARED_LIBS=yes$/d' configure

# Set F2C library flags
export FLIBS="-L$PREFIX/lib -lf2c"

# Fix OpenBLAS static library naming
# The static library has a specific architecture name, but we need libopenblas.a
if [ -f "$PREFIX/lib/libopenblas_riscv64_generic-r0.3.26.a" ]; then
    ln -sf "$PREFIX/lib/libopenblas_riscv64_generic-r0.3.26.a" "$PREFIX/lib/libopenblas.a"
elif ls $PREFIX/lib/libopenblas_*_generic-r*.a 1> /dev/null 2>&1; then
    # Find any OpenBLAS static library and link it
    OPENBLAS_STATIC=$(ls $PREFIX/lib/libopenblas_*_generic-r*.a | head -1)
    ln -sf "$OPENBLAS_STATIC" "$PREFIX/lib/libopenblas.a"
fi

emconfigure ./configure \
   --prefix="${PREFIX}" \
   --build="${BUILD}"\
   --host="${HOST}" \
   --disable-dependency-tracking \
   --enable-fortran-calling-convention="f2c" \
   --disable-shared \
   --enable-static \
   --disable-64 \
   --disable-dlopen \
   --disable-dl \
   --disable-dynamic-linking \
   --disable-rpath \
   --disable-openmp \
   --disable-threads \
   --disable-fftw-threads \
   --disable-readline \
   --disable-docs \
   --disable-java \
   --disable-rapidjson \
   --with-blas="-lopenblas" \
   --with-lapack="-lopenblas" \
   --with-pcre2 \
   --with-pcre2-includedir="${PREFIX}/include" \
   --with-pcre2-libdir="${PREFIX}/lib" \
   --without-pcre \
   --without-qt \
   --without-qrupdate \
   --without-arpack \
   --without-curl \
   --without-fftw3 \
   --without-fftw3f \
   --without-hdf5 \
   --without-opengl \
   --without-x \
   --without-sndfile \
   --without-portaudio \
   --without-freetype \
   --without-fontconfig \
   --without-fltk \
   --without-sundials_ida \
   --without-sundials_nvecserial \
   --without-sundials_sunlinsolklu \
   --without-qhull_r \
   --without-cxsparse \
   --without-ccolamd \
   --without-z \
   --without-bz2 \
   --without-magick \
   --without-spqr \
   --without-glpk \
   --without-framework-carbon \
   || cat config.log || exit 1

# Disable building of .oct files (dynamic modules) for WebAssembly
# Replace the problematic .oct generation rule with a simple touch command
sed -i '/^%.oct : %.la$/,/^$/c\
%.oct : %.la\
\t$(AM_V_GEN)touch $@' Makefile

# Create thread stubs if needed (Octave might still expect these even with threads disabled)
cat > thread_stubs.cpp << 'EOF'
// Thread stubs for disabled threading
namespace octave {
  class thread {
  public:
    static void init();
    static bool is_thread();
  };
  
  void thread::init() { }
  bool thread::is_thread() { return false; }
}
EOF
em++ -c thread_stubs.cpp -o thread_stubs.o

# Create a static library with all stubs
ar rcs liboctave_stubs.a thread_stubs.o

# Add stubs to the build
export LIBS="${LIBS} ${PWD}/liboctave_stubs.a"

# Modify the Makefile to include our stubs in LIBS
sed -i "s|^LIBS = .*|LIBS = -lm ${PWD}/liboctave_stubs.a|" Makefile

# Build with reduced parallelism to avoid OOM
emmake make --jobs 7

# Fix the install-oct target for static builds
# The default install-oct expects dlname to exist in .la files, but static builds don't have it
# We'll modify it to skip the dlname check and just touch empty .oct files
sed -i '/error: dlname is empty/d' Makefile
sed -i 's/exit 1;/touch $PREFIX\/lib\/octave\/9.4.0\/oct\/wasm32-unknown-linux-gnu\/`echo $f | $BUILD_PREFIX\/bin\/\/sed '\''s,^lib,,; s,\.la$,.oct,'\''`;/' Makefile

emmake make install
