#!/bin/sh
# Catch code the compiler silently deleted: list readable strings present in the official release
# DLL but missing from ours. clang removes code paths that rely on undefined behaviour MSVC
# tolerates, and a vanished log message is the easiest symptom to spot.
# usage: check-strings.sh <our.dll> [release-tag]   (default tag from wc4w_en/version.h)
# Exit 1 if anything unexpected is missing. Compare against the release your source matches.
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
ours=$1
name=$(basename "$ours")
if [ -n "${2:-}" ]; then tag=$2; else
  v=$(tr -d '\r' < "$root/wc4w_en/version.h" | awk '/#define VERSION_(MAJOR|MINOR|REVISION) /{printf "%s%s", s, $3; s="."}')
  tag=wc4w_en_v$v
fi
ver=${tag#wc4w_en_v}
case "$name" in dwrap.dll) zip=wc4w_en_DVD_$ver.zip ;; *) zip=wc4w_en_$ver.zip ;; esac
ref=${WC4_DEPS:-$root/.deps}/ref/$tag
if [ ! -f "$ref/$name" ]; then
  mkdir -p "$ref"
  curl -fsL -o "$ref/$zip" "https://github.com/mattwells77/Wing_Commander_IV_Enhancement_Patch/releases/download/$tag/$zip"
  (cd "$ref" && bsdtar xf "$zip" 2>/dev/null || unzip -oq "$zip")
fi
[ -f "$ref/$name" ] || { echo "no $name in $zip" >&2; exit 1; }

t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
for f in ref ours; do
  [ $f = ref ] && d="$ref/$name" || d=$ours
  { strings -a -n 8 "$d"; strings -a -n 8 -e l "$d"; } | sort -u > "$t/$f"
done
# Expected differences: build paths and section names, MSVC RTTI names, manifests, and short
# std::string literals clang stores as immediates instead of string data.
comm -23 "$t/ref" "$t/ours" | grep -E '[a-z]{3,}' \
  | grep -vE '^[A-Za-z0-9_@?$]+$|^\.|^[A-Z]:\\|lambda_|<\?xml|<assembly|DOS mode|C\+\+/WinRT version|^\[(English|German|French)\]$|^vector too long$|^ddraw\.dll$|^dwrap\.dll$' \
  > "$t/missing" || true
# Strings that only moved are fine. `strings` can glue a stray byte from the neighbouring data
# onto the front ("S\presets", "ecombase.dll"), so also accept a match without the first char.
: > "$t/real"
while IFS= read -r s; do
  grep -qF -- "$s" "$t/ours" || grep -qF -- "${s#?}" "$t/ours" || printf '%s\n' "$s" >> "$t/real"
done < "$t/missing"
if [ -s "$t/real" ]; then
  echo "Strings in $tag $name missing from $ours:"; sed 's/^/  /' "$t/real"; exit 1
fi
echo "OK: no unexpected strings missing vs $tag $name"
