# xeus-octave WebAssembly Build Troubleshooting

## Function Signature Mismatch Errors

### Problem
```
wasm-ld: error: function signature mismatch: dhgeqz_
>>> defined as (i32, i32, ..., i32) -> i32 in liboctinterp.a
>>> defined as (i32, i32, ..., i32) -> i32 in libclapack_all.a
```

### Root Cause
This occurs because:
1. Octave was built with CLAPACK and contains BLAS/LAPACK symbols in its static libraries
2. xeus-octave is trying to link against CLAPACK directly, causing duplicate symbols
3. The signatures differ because Octave adds f2c calling convention wrappers

### Solution
The build script now:
1. Removes `-lclapack_all` from Octave's pkg-config files
2. Hides CLAPACK during xeus-octave build to prevent direct linking
3. Relies on BLAS/LAPACK symbols already present in Octave's libraries

## Missing BLAS/LAPACK Symbols

### Problem
```
undefined reference to 'dgemm_'
```

### Root Cause
This happens if Octave's static libraries don't contain the expected BLAS/LAPACK symbols.

### Solution
1. Verify Octave was built with CLAPACK:
   ```bash
   ar t $PREFIX/lib/octave/9.4.0/liboctave.a | grep -E "(dgemm|blas|lapack)"
   ```

2. Ensure the build script doesn't hide CLAPACK too early
3. Check that Octave's pkg-config files are correctly modified

## Thread Stub Issues

### Problem
```
wasm-ld: error: nested archives are not supported
```

### Root Cause
Octave's WASM build embeds `liboctave_stubs.a` inside its static libraries.

### Solution
The build script removes these embedded archives:
```bash
ar d $PREFIX/lib/octave/9.4.0/liboctinterp.a liboctave_stubs.a
ar d $PREFIX/lib/octave/9.4.0/liboctave.a liboctave_stubs.a
```

## Build Configuration Issues

### Debugging Steps
1. Check CMake configuration:
   ```bash
   grep -i "blas\|lapack" build/CMakeCache.txt
   ```

2. Verify pkg-config output:
   ```bash
   pkg-config --libs octave
   pkg-config --libs octinterp
   ```

3. List symbols in Octave libraries:
   ```bash
   nm -g $PREFIX/lib/octave/9.4.0/liboctave.a | grep -E "T.*gemm"
   ```

### Clean Build
If issues persist:
```bash
rm -rf build
rm -rf $PREFIX/lib/.hidden_clapack
# Then rebuild
``` 