#!/bin/bash

# The archive's contents have default permission 0750. If we use docker
# to build, then we will not own the contents in the host, which means
# we cannot navigate into the folder. Setting it to 0750 makes it
# easier to debug.
chmod -R o+rx .

export AR=emar
export ARCH=emar
export RANLIB=emranlib

cp $RECIPE_DIR/patches/endfile.c  ./F2CLIBS/libf2c/

# In CLAPACK's Makefiles, some commands are mistakenly (?) hardcoded
# instead of using the right variables
sed -i 's/^	-ranlib /^	$(RANLIB)/' **/Makefile
sed -i 's/^	ar /^	$(ARCH)/' **/Makefile
sed -i 's/^	ld /^	$(LD)/' **/Makefile

sed -i 's/-ranlib/-emranlib/g' F2CLIBS/libf2c/Makefile
sed -i 's/\bar\b/emar/g' F2CLIBS/libf2c/Makefile

export CFLAGS="CFLAGS -DNO_TRUNCATE"

emmake make -j ${CPU_COUNT} blaslib lapacklib

# Copy and compile the gejsv stubs
cp $RECIPE_DIR/gejsv_stubs.c .
emcc -c gejsv_stubs.c -I./INCLUDE -I./F2CLIBS/libf2c -o gejsv_stubs.o

mkdir -p ${PREFIX}/lib

# Create a temporary directory to combine archives
mkdir -p clapack_all
cd clapack_all

# Extract all object files from the archives
emar x ../blas_WA.a
emar x ../lapack_WA.a
emar x ../F2CLIBS/libf2c.a

# Copy the gejsv stubs
cp ../gejsv_stubs.o .

# Create a single, flat static library from all the object files
emar rcs ../libclapack_all.a *.o

# Move back to the parent directory and clean up
cd ..
rm -rf clapack_all

# Copy the new static library to the installation directory
cp libclapack_all.a ${PREFIX}/lib/

# emcc blas_WA.a lapack_WA.a F2CLIBS/libf2c.a -sSIDE_MODULE -o ${PREFIX}/lib/clapack_all.so

mkdir -p ${PREFIX}/include
cp INCLUDE/clapack.h ${PREFIX}/include