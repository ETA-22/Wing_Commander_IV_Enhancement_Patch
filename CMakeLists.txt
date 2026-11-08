# Linux cross-build of wc4w_en with clang-cl (the Visual Studio solution is unchanged and remains
# the primary build). See docs/building-on-linux.md.
#
#   tools/linux/bootstrap.sh --accept-license
#   cmake -G Ninja -B build -DCMAKE_TOOLCHAIN_FILE=cmake/clang-cl-x86.cmake -DCMAKE_BUILD_TYPE=Release
#   ninja -C build
cmake_minimum_required(VERSION 3.20)
project(wc4w_en CXX RC)

if(NOT CMAKE_CXX_COMPILER_ID STREQUAL "Clang" OR NOT CMAKE_CXX_SIMULATE_ID STREQUAL "MSVC")
  message(FATAL_ERROR "Use the clang-cl toolchain: -DCMAKE_TOOLCHAIN_FILE=cmake/clang-cl-x86.cmake")
endif()

option(WC4_DVD "DVD / 30th Anniversary build (dwrap.dll, VERSION_WC4_DVD). OFF builds ddraw.dll for WC4W.EXE." ON)
set(VLC_SDK "${WC4_DEPS}/vlc-3.0.21/sdk" CACHE PATH "VLC 3.0.21 win32 SDK")
set(LIBVLCPP "${WC4_DEPS}/libvlcpp" CACHE PATH "libvlcpp checkout (tag v3.0.0)")

set(SRC "${CMAKE_SOURCE_DIR}/wc4w_en")
set(VCXPROJ "${SRC}/wc4w_en.vcxproj")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${VCXPROJ}")

# Take the source lists from the Visual Studio project so the two builds can't drift apart.
file(STRINGS "${VCXPROJ}" _cl REGEX "<ClCompile Include=\"[^\"]+\"")
file(STRINGS "${VCXPROJ}" _rc REGEX "<ResourceCompile Include=\"[^\"]+\"")
set(CPP_SOURCES "")
foreach(l IN LISTS _cl)
  string(REGEX REPLACE ".*Include=\"([^\"]+)\".*" "\\1" f "${l}")
  list(APPEND CPP_SOURCES "${SRC}/${f}")
endforeach()

# llvm-rc can't read UTF-16 .rc files: convert those to UTF-8 in the build tree at build time.
# Others are Windows-1252, the code page Visual Studio's rc.exe assumes.
set(RC_SOURCES "")
foreach(l IN LISTS _rc)
  string(REGEX REPLACE ".*Include=\"([^\"]+)\".*" "\\1" f "${l}")
  file(READ "${SRC}/${f}" _bom LIMIT 2 HEX)
  if(_bom STREQUAL "fffe")
    set(out "${CMAKE_BINARY_DIR}/gen/${f}")
    add_custom_command(OUTPUT "${out}"
      COMMAND ${CMAKE_COMMAND} -E make_directory "${CMAKE_BINARY_DIR}/gen"
      COMMAND sh -c "iconv -f UTF-16LE -t UTF-8 \"$0\" | sed '1s/^\\xEF\\xBB\\xBF//' > \"$1\"" "${SRC}/${f}" "${out}"
      DEPENDS "${SRC}/${f}" VERBATIM)
    set_source_files_properties("${out}" PROPERTIES COMPILE_FLAGS "/C 65001")
    list(APPEND RC_SOURCES "${out}")
  else()
    set_source_files_properties("${SRC}/${f}" PROPERTIES COMPILE_FLAGS "/C 1252")
    list(APPEND RC_SOURCES "${SRC}/${f}")
  endif()
endforeach()

# Header / import-library names whose case differs from the files on disk.
execute_process(COMMAND sh "${CMAKE_SOURCE_DIR}/tools/linux/casefix.sh" "${SRC}" "${CMAKE_BINARY_DIR}/casefix" "${WC4_DEPS}/xwin"
  RESULT_VARIABLE _rv)
if(NOT _rv EQUAL 0)
  message(FATAL_ERROR "casefix.sh failed")
endif()

if(WC4_DVD)
  set(OUT_NAME dwrap)
else()
  set(OUT_NAME ddraw)
endif()

add_library(wc4w_en SHARED ${CPP_SOURCES} ${RC_SOURCES} "${SRC}/exports.def")
set_target_properties(wc4w_en PROPERTIES OUTPUT_NAME ${OUT_NAME} MSVC_RUNTIME_LIBRARY MultiThreadedDLL)
target_compile_definitions(wc4w_en PRIVATE WIN32 NDEBUG WC4WEN_EXPORTS _WINDOWS _USRDLL UNICODE _UNICODE
  $<$<BOOL:${WC4_DVD}>:VERSION_WC4_DVD>)
target_include_directories(wc4w_en PRIVATE
  "${CMAKE_SOURCE_DIR}/cmake/compat"      # <experimental/coroutine> stub, see the header
  "${SRC}" "${VLC_SDK}/include" "${LIBVLCPP}")
target_include_directories(wc4w_en SYSTEM PRIVATE "${CMAKE_BINARY_DIR}/casefix/include")
# /std:c++20: C++/WinRT needs it under clang (VS builds as C++17). /Z7 + /DEBUG: line-level PDB.
# MSVC accepts narrowing in brace initialisers (libvlc_Movies.cpp); clang errors by default.
target_compile_options(wc4w_en PRIVATE /std:c++20 /EHsc /O2 /permissive- /Z7 /Brepro
  -Wno-error=c++11-narrowing -Werror=return-type
  -Wno-nonportable-include-path)          # mixed-case includes, handled by casefix.sh
target_link_directories(wc4w_en PRIVATE "${CMAKE_BINARY_DIR}/casefix/lib" "${VLC_SDK}/lib")
# runtimeobject.lib: Ro* imports for C++/WinRT (the VS build gets WindowsApp.lib from the CppWinRT NuGet package).
target_link_libraries(wc4w_en PRIVATE runtimeobject.lib)
# /Brepro (here and on the compiler): identical source gives an identical DLL.
target_link_options(wc4w_en PRIVATE /SAFESEH:NO /DEBUG /OPT:REF /OPT:ICF /Brepro)
