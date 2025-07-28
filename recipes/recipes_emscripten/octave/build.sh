#!/bin/bash
# built in a different repo
set -e # Exit on error

# --- Custom Toolchain Setup ---
# The core of this strategy is to build the exact same f2c and fort77 wrapper
# as the reference Dockerfile. This ensures 100% toolchain compatibility.

mkdir -p local_bin
export PATH=${PWD}/local_bin:${PATH}

# 1. Build f2c from source
echo "--- Building f2c from source ---"
curl -L https://www.netlib.org/f2c/src.tgz -o f2c.tar.gz
mkdir -p f2c
tar -zxf f2c.tar.gz -C f2c
cd f2c
# We must build f2c with the native compiler, not emcc.
# Unsetting LDFLAGS in a subshell prevents emscripten flags from leaking into this native build.
(unset LDFLAGS && make -j${CPU_COUNT} -C src -f makefile.u all)
cp src/f2c ../local_bin/
cd ..


# 2. Build the fort77 wrapper script
echo "--- Building fort77 wrapper ---"
git clone https://salsa.debian.org/debian/fort77.git
cd fort77
autoreconf -fi
# This is a host tool, so it must be built with the native compiler, not emmake.
make F2C=${PWD}/../local_bin/f2c fort77
cp fort77 ../local_bin/
cd ..

# Set F77 to our newly built wrapper with full path
export F77="${PWD}/local_bin/fort77"
export FC="${PWD}/local_bin/fort77"


# 3. Build libf2c from source (critical for consistency)
echo "--- Building libf2c from source ---"
# Using the same version as the Dockerfile
curl -L https://www.netlib.org/f2c/libf2c.zip -o libf2c.zip
unzip -q libf2c.zip -d libf2c
cd libf2c
# Build static library for our static build
emmake make -j${CPU_COUNT} all
cp libf2c.a ../local_bin/
# Also copy the header
cp f2c.h ../local_bin/
cd ..


# --- Build LAPACK 3.4.2 from Source ---
# With our new toolchain, this build should now succeed.

LAPACK_VERSION="3.4.2"
echo "--- Downloading and building LAPACK ${LAPACK_VERSION} ---"
curl -L http://www.netlib.org/lapack/lapack-${LAPACK_VERSION}.tgz -o lapack.tgz
tar -zxf lapack.tgz
cd lapack-${LAPACK_VERSION}

# Create a make.inc file for Emscripten
cat > make.inc << 'MAKEINC_EOF'
SHELL = /bin/sh
FORTRAN  = $(F77)
OPTS     = -O0
DRVOPTS  = $(OPTS)
NOOPT    = -O0
LOADER   = $(FORTRAN)
LOADOPTS =
TIMER    =
ARCH     = emar
ARCHFLAGS= cr
RANLIB   = emranlib
BLASLIB      = ../../librefblas.a
LAPACKLIB    = ../../liblapack.a
MAKEINC_EOF

# Build BLAS library
echo "Building BLAS..."
emmake make -j${CPU_COUNT} F77=${F77} INCDIR=${PWD}/../local_bin blaslib
cp blas_LINUX.a ../librefblas.a

# Build LAPACK library
echo "Building LAPACK..."
emmake make -j${CPU_COUNT} F77=${F77} INCDIR=${PWD}/../local_bin lapacklib
cp lapack_LINUX.a ../liblapack.a

cd ..
echo "--- LAPACK build complete ---"


# --- Configure Octave ---
# Remove spaces in `-s OPTION` from emscripten to avoid confusion
export LDFLAGS="$(echo "${LDFLAGS}" |  sed -E 's/-s +/-s/g')"
export LDFLAGS="${LDFLAGS} -Wl,--allow-multiple-definition"

# From the reference Dockerfile: critical flags
export LDFLAGS="${LDFLAGS} -s ERROR_ON_UNDEFINED_SYMBOLS=0 -L${PWD}/local_bin -O0"
export CFLAGS="${CFLAGS} -I${PWD}/local_bin -O0"
export CXXFLAGS="${CXXFLAGS} -std=c++11 -I${PWD}/local_bin -O0 -fwasm-exceptions"
export FFLAGS="-I${PWD}/local_bin -O0 -E"
export FLIBS=""

# Emscripten-specific environment variables from Dockerfile
export EMCC_FORCE_STDLIBS=1
export EMCONFIGURE_JS=1
export BUILD_EXEEXT=.js

# Force disable pthread for WebAssembly compatibility
sed -i 's/ax_pthread_ok=yes/ax_pthread_ok=no/' configure
export ac_cv_header_pthread_h=no

BUILD="x86_64-unknown-linux-gnu"
HOST="wasm32-local-emscripten"

# Regenerate configure script (from Dockerfile)
echo "Regenerating configure script..."
rm -f configure
autoreconf

# Manually set FORTRAN name-mangling to use lower-case and single underscore
sed -i -e 's/(name,NAME) name"/(name,NAME) name ## _"/g' configure

# Point to our custom-built LAPACK/BLAS and libf2c
BLAS_LIBS_PATH="${PWD}/librefblas.a"
F2C_LIBS_PATH="${PWD}/local_bin/libf2c.a -lm"

export BLAS_LIBS="${BLAS_LIBS_PATH} ${F2C_LIBS_PATH}"
export LAPACK_LIBS="${PWD}/liblapack.a ${BLAS_LIBS}"

# Create thread stubs for disabled threading
echo "Creating thread stubs..."
cat > thread_stubs.cpp << 'EOF'
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
emar rcs liboctave_stubs.a thread_stubs.o
export LIBS="${LIBS} ${PWD}/liboctave_stubs.a"

# Configure Octave
./configure --prefix=$PREFIX \
            --build=${BUILD} \
            --host=${HOST} \
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
            --with-blas="${BLAS_LIBS}" \
            --with-lapack="${LAPACK_LIBS}" \
            --with-pcre2 \
            --with-pcre2-includedir=$PREFIX/include \
            --with-pcre2-libdir=$PREFIX/lib \
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
            --without-framework-carbon

# --- Post-Configure Patches ---
# Disable .oct file generation (unsupported in WASM)
echo "Patching Makefiles to disable .oct file generation..."
find . -name "Makefile" -exec sed -i '/^%.oct : %.la$/,/^$/c\
%.oct : %.la\
\t$(AM_V_GEN)touch $@' {} \;

# --- Build and Install ---
emmake make -j${CPU_COUNT}
emmake make install
