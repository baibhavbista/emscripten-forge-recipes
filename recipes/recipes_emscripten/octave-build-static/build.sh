#!/bin/bash
set -ex

# The source for this recipe is our pre-built tarball. The build system
# automatically extracts it into the current directory ($SRC_DIR).

# printout working dir
pwd

# Our goal is to "install" these pre-built files into the package's
# final location, which is represented by the $PREFIX variable.

# We use 'cp -a' to preserve file attributes and copy recursively.
cp -a ./* "${PREFIX}/"

echo "Successfully installed pre-built Octave package." 