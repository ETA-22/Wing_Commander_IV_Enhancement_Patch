#!/bin/sh
# Windows headers/libs are case-insensitive; Linux paths are not. For every header or import
# library the sources name with a different case than the file on disk, create a correctly
# named symlink under <outdir>/include or <outdir>/lib. Called by CMake at configure time.
# usage: casefix.sh <srcdir> <outdir> <xwin-root>
set -eu
src=$1; out=$2; xwin=$3
rm -rf "$out"; mkdir -p "$out/include" "$out/lib"
incdirs="$xwin/crt/include $xwin/sdk/include/ucrt $xwin/sdk/include/um $xwin/sdk/include/shared"
libdirs="$xwin/crt/lib/x86 $xwin/sdk/lib/um/x86 $xwin/sdk/lib/ucrt/x86"

# link <name> <outsubdir> <dirs...>: nothing to do if <name> exists as spelled in any dir
link() {
  name=$1; sub=$2; shift 2
  for d in "$@"; do [ -e "$d/$name" ] && return 0; done
  for d in "$@"; do
    m=$(find "$d" -maxdepth 1 -iname "$(basename "$name")" 2>/dev/null | head -n 1)
    if [ -n "$m" ]; then
      mkdir -p "$out/$sub/$(dirname "$name")"
      ln -sf "$m" "$out/$sub/$name"
      echo "casefix: $name -> $m"
      return 0
    fi
  done
}

files=$(find "$src" -maxdepth 1 -type f \( -name '*.h' -o -name '*.cpp' \))
for h in $(cat $files | tr -d '\r' | sed -n 's/^[[:space:]]*#[[:space:]]*include[[:space:]]*<\([^>]*\)>.*/\1/p' | sort -u); do
  link "$h" include $incdirs
done
for h in $(cat $files | tr -d '\r' | sed -n 's/^[[:space:]]*#[[:space:]]*include[[:space:]]*"\([^"]*\)".*/\1/p' | sort -u); do
  link "$h" include "$src" "$src/$(dirname "$h")"
done
for l in $(cat $files | tr -d '\r' | sed -n 's/.*#[[:space:]]*pragma[[:space:]]*comment[[:space:]]*([[:space:]]*lib[[:space:]]*,[[:space:]]*"\([^"]*\)".*/\1/p' | sort -u); do
  link "$l" lib $libdirs
done
