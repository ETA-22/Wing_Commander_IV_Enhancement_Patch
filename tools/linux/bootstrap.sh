#!/bin/sh
# Fetch everything the Linux cross-build needs into .deps/ (or $WC4_DEPS):
#   - xwin 0.10.0 and, through it, the Windows SDK + MSVC CRT for x86 (Microsoft's license applies)
#   - VLC 3.0.21 win32 SDK (sha256-checked against VideoLAN's published hash)
#   - libvlcpp at tag v3.0.0 (its master branch targets the VLC 4 API)
# usage: tools/linux/bootstrap.sh --accept-license
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
deps=${WC4_DEPS:-$root/.deps}
XWIN_VERSION=0.10.0
VLC_URL=https://download.videolan.org/pub/videolan/vlc/3.0.21/win32/vlc-3.0.21-win32.7z
VLC_SHA256=77b2a79c4baf0dcc7c453f74f29fbdb55d42c790d277b5f9e0dbed0f3abc0131
LIBVLCPP_COMMIT=3f9e8d1546771984be7393f660abe4e96e9a93d4   # tag v3.0.0

if [ "${1:-}" != "--accept-license" ]; then
  echo "This downloads the Microsoft Windows SDK and MSVC CRT, which are covered by Microsoft's"
  echo "license (https://go.microsoft.com/fwlink/?LinkId=2086102). Re-run with --accept-license."
  exit 2
fi

missing=""
for t in clang-cl lld-link llvm-rc llvm-mt cmake ninja cargo git curl iconv sha256sum; do
  command -v $t >/dev/null 2>&1 || missing="$missing $t"
done
command -v 7z >/dev/null 2>&1 || command -v bsdtar >/dev/null 2>&1 || missing="$missing 7z|bsdtar"
[ -z "$missing" ] || { echo "missing tools:$missing" >&2; exit 1; }

mkdir -p "$deps"; cd "$deps"

if [ ! -x cargo/bin/xwin ] || ! cargo/bin/xwin --version | grep -q "$XWIN_VERSION"; then
  echo "== installing xwin $XWIN_VERSION"
  cargo install --locked --root "$deps/cargo" xwin --version "$XWIN_VERSION"
fi
if [ ! -d xwin/crt/include ]; then
  echo "== downloading Windows SDK + CRT (x86, ~1 GB)"
  cargo/bin/xwin --accept-license --arch x86 --cache-dir xwin-cache splat --output xwin --include-debug-libs --preserve-ms-arch-notation
  rm -rf xwin-cache
fi

if [ ! -d vlc-3.0.21/sdk ]; then
  echo "== downloading VLC 3.0.21 SDK"
  curl -fL -o vlc.7z "$VLC_URL"
  echo "$VLC_SHA256  vlc.7z" | sha256sum -c -
  if command -v 7z >/dev/null 2>&1; then
    7z x -y -bd vlc.7z 'vlc-3.0.21/sdk/*' >/dev/null
  else
    bsdtar xf vlc.7z 'vlc-3.0.21/sdk/*'
  fi
  rm -f vlc.7z
fi

if [ ! -d libvlcpp/.git ]; then
  echo "== fetching libvlcpp"
  git clone -q https://github.com/videolan/libvlcpp.git libvlcpp
fi
git -C libvlcpp -c advice.detachedHead=false checkout -q "$LIBVLCPP_COMMIT"

echo "== done. Next:"
echo "   cmake -G Ninja -S \"$root\" -B \"$root/build\" -DCMAKE_TOOLCHAIN_FILE=cmake/clang-cl-x86.cmake -DCMAKE_BUILD_TYPE=Release"
echo "   ninja -C \"$root/build\""
