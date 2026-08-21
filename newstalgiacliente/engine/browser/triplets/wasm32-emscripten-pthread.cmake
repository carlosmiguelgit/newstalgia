set(VCPKG_TARGET_ARCHITECTURE wasm32)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)

set(VCPKG_CMAKE_SYSTEM_NAME Emscripten)
if(DEFINED ENV{EMSDK})
  set(_EMSDK_ROOT "$ENV{EMSDK}")
else()
  set(_EMSDK_ROOT "D:/emsdk")
endif()
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "${_EMSDK_ROOT}/upstream/emscripten/cmake/Modules/Platform/Emscripten.cmake")

# emcc.exe (pylauncher) on Windows needs python.exe (or EMSDK_PYTHON) in its
# environment when spawned from a sanitized environment (e.g. vcpkg detection).
set(ENV{EMSDK_PYTHON} "${_EMSDK_ROOT}/python/3.13.3_64bit/python.exe")
set(ENV{PATH} "${_EMSDK_ROOT}/python/3.13.3_64bit;${_EMSDK_ROOT}/upstream/emscripten;${_EMSDK_ROOT}/node/24.19.0_64bit;${_EMSDK_ROOT}/upstream/bin;$ENV{PATH}")

# Force pthread support with atomics and bulk-memory for all packages
# These flags are required for shared memory support in WebAssembly
set(VCPKG_C_FLAGS "-pthread -matomics -mbulk-memory")
set(VCPKG_CXX_FLAGS "-pthread -matomics -mbulk-memory")
set(VCPKG_LINKER_FLAGS "-pthread -matomics -mbulk-memory")

# Also set as CMAKE_*_FLAGS to ensure they're applied universally
set(VCPKG_CMAKE_CONFIGURE_OPTIONS 
    "-DCMAKE_C_FLAGS=-pthread -matomics -mbulk-memory"
    "-DCMAKE_CXX_FLAGS=-pthread -matomics -mbulk-memory"
)
