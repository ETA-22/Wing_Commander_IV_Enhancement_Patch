# Building on Linux

`wc4w_en` can be cross-compiled on Linux with clang-cl, with no Windows machine or Visual Studio. The Visual Studio solution is unchanged and is still the primary build. This build reads its source list from `wc4w_en/wc4w_en.vcxproj`, so the two stay in sync.

The output is a 32-bit Windows DLL that imports the same DLLs as the official release.

## Requirements

- LLVM/clang with `clang-cl`, `lld-link`, `llvm-rc` and `llvm-mt` (tested with clang 23)
- `cmake` (3.20 or newer) and `ninja`
- `cargo` (to install [xwin](https://github.com/Jake-Shadle/xwin))
- `git`, `curl`, `iconv`, `sha256sum`, and either `7z` or `bsdtar`

## Build

```sh
tools/linux/bootstrap.sh --accept-license
cmake -G Ninja -B build -DCMAKE_TOOLCHAIN_FILE=cmake/clang-cl-x86.cmake -DCMAKE_BUILD_TYPE=Release
ninja -C build
```

`bootstrap.sh` fetches its dependencies into `.deps/`, or into `$WC4_DEPS` if that is set:

- the Windows SDK and MSVC CRT for x86, via xwin (about 1 GB, covered by Microsoft's license)
- the VLC 3.0.21 win32 SDK, checked against VideoLAN's published sha256
- libvlcpp at tag `v3.0.0`

The build produces `build/dwrap.dll`, the DVD / 30th Anniversary flavour (`Release DVD` in Visual Studio). Configure with `-DWC4_DVD=OFF` to get `ddraw.dll` for `WC4W.EXE` instead (`Release` in Visual Studio). Builds are reproducible: the same source and build folder give a byte-identical DLL.

## Check for silently deleted code

```sh
tools/linux/check-strings.sh build/dwrap.dll [wc4w_en_vX.Y.Z]
```

clang optimises away code paths that depend on undefined behaviour that MSVC happens to tolerate. One example is reading an uninitialised member. When that happens, the game crashes, or a feature quietly stops working. This script downloads the matching official release and lists any readable strings, mostly log messages, that it has and our DLL lacks. Run it against the release your source corresponds to. By default that is the version in `wc4w_en/version.h`.

## Deploy

```sh
WC4_HOST=deck@steamdeck WC4_GAME_DIR="/path/to/Wing Commander IV/WC4_Enhanced" tools/linux/deploy.sh build/dwrap.dll
WC4_HOST=... WC4_GAME_DIR=... tools/linux/deploy.sh --restore dwrap.dll
```

The first deploy keeps the installed DLL as `<name>.bak-orig`. `--restore` puts it back. For a host that only accepts a password, install `sshpass` and set `SSHPASS`.

## Differences from the Visual Studio build

- **C++20 instead of C++17.** clang does not support C++ coroutines for 32-bit MSVC targets, so C++/WinRT's headers fall back to `<experimental/coroutine>`, which refuses clang. `cmake/compat/experimental/coroutine` stubs out the names. The patch never uses `co_await`.
- **Case-insensitive names.** `tools/linux/casefix.sh` symlinks headers and import libraries whose case in the source differs from the file on disk, such as `Shlobj.h` and `ShlObj.h`.
- **Resource encodings.** `joystick_config.rc` is UTF-16, which llvm-rc can't read, so it is converted to UTF-8 in the build tree. The other resource files are compiled as Windows-1252.
- **WinRT imports.** The build links `runtimeobject.lib`, which provides what the CppWinRT NuGet package's `WindowsApp.lib` does for Visual Studio.
- **Narrowing in brace initialisers.** This stays a warning, matching MSVC. A missing `return` in a non-void function is an error.
