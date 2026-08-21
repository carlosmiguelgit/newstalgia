project(otclient)

# *****************************************************************************
# Options
# *****************************************************************************

option(TOGGLE_FRAMEWORK_GRAPHICS "Use Graphics " ON)
option(TOGGLE_FRAMEWORK_SOUND "Use SOUND " ON)
option(TOGGLE_FRAMEWORK_XML "Use XML " ON)
option(TOGGLE_FRAMEWORK_NET "Use NET " ON)
option(TOGGLE_FRAMEWORK_PROTOBUF "Use Protobuf" ON)
option(TOGGLE_FRAMEWORK_EDITOR "Use Editor " OFF)
option(TOGGLE_BIN_FOLDER "Use build/bin folder for generate compilation files" OFF)
option(DEBUG_LOG "Enable Debug Log" OFF)
option(ASAN_ENABLED "Build this target with AddressSanitizer" OFF)
option(BUILD_STATIC_LIBRARY "Build using static libraries" OFF)
option(TOGGLE_PRE_COMPILED_HEADER "Use precompiled header (speed up compile)" ON)
option(SPEED_UP_BUILD_UNITY "Compile using build unity for speed up build" ON)

if (TOGGLE_FRAMEWORK_PROTOBUF)
  # Protobuf
  add_subdirectory(protobuf)
endif()

# *****************************************************************************
# Cmake Features
# *****************************************************************************
set(GNUCXX_MINIMUM_VERSION 9)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)


# Make will print more details
set(CMAKE_VERBOSE_MAKEFILE OFF)

# Generate compile_commands.json
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# *****************************************************************************
# Client
# *****************************************************************************
add_executable(${PROJECT_NAME} "")

if(NOT OTCLIENT_BUILD_CLIENT)
  set_target_properties(${PROJECT_NAME} PROPERTIES EXCLUDE_FROM_ALL ON)
endif()

# *****************************************************************************
# Options Code
# *****************************************************************************

# Define Framework options for use in compilation
set(FRAMEWORK_DEFINITIONS "")
if (TOGGLE_FRAMEWORK_GRAPHICS)
  set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DFRAMEWORK_GRAPHICS)
endif()
if (TOGGLE_FRAMEWORK_SOUND)
  set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DFRAMEWORK_SOUND)
endif()
if (TOGGLE_FRAMEWORK_XML)
  set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DFRAMEWORK_XML)
endif()
if (TOGGLE_FRAMEWORK_NET)
  set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DFRAMEWORK_NET)
endif()
if (TOGGLE_FRAMEWORK_PROTOBUF)
  set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DFRAMEWORK_PROTOBUF)
endif()

if (TOGGLE_FRAMEWORK_EDITOR)
  set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DFRAMEWORK_EDITOR)
endif()
set(FRAMEWORK_DEFINITIONS ${FRAMEWORK_DEFINITIONS} -DOPENGL_ES=2)

set(VERSION "1.0.0")

# *****************************************************************************
# Definitions code
# *****************************************************************************

# *****************************************************************************
# Sanity Check
# *****************************************************************************

# === GCC Minimum Version ===
if (CMAKE_COMPILER_IS_GNUCXX)
  if (CMAKE_CXX_COMPILER_VERSION VERSION_LESS GNUCXX_MINIMUM_VERSION)
    message(FATAL_ERROR "GCC version must be at least ${GNUCXX_MINIMUM_VERSION}!")
  endif()
endif()


# Multiprocessor compiller
if(CMake_MSVC_PARALLEL)
  if(CMake_MSVC_PARALLEL GREATER 0)
    add_definitions(/MP${CMake_MSVC_PARALLEL})
  else()
    add_definitions(/MP)
  endif()
endif()


# Client options
add_definitions(-DCLIENT)
add_definitions(-DNOMINMAX)
add_definitions(${FRAMEWORK_DEFINITIONS})
add_definitions(-D"VERSION=${VERSION}")
# === Build options ===
message(STATUS "Build type: " ${CMAKE_BUILD_TYPE})
add_definitions(-D"BUILD_TYPE=\\\"${CMAKE_BUILD_TYPE}\\\"")
message(STATUS "Build commit: ${BUILD_COMMIT}")
add_definitions(-D"BUILD_COMMIT=\\\"${BUILD_COMMIT}\\\"")
message(STATUS "Build revision: ${BUILD_REVISION}")
add_definitions(-D"BUILD_REVISION=\\\"${BUILD_REVISION}\\\"")


# *****************************************************************************
# Packages / Libs
# *****************************************************************************
# Before we begin loading packages wholesale, we have to check which package
# provider is available. Normally, OTClient developers prefer vcpkg.
# However if that is not available, we can check if PkgConfig is available.
# PkgConfig is only intended for package maintainers.
# *****************************************************************************
if(NOT DEFINED VCPKG_TARGET_TRIPLET)
  find_package(PkgConfig REQUIRED)
endif()
find_package(OpenSSL QUIET)
find_package(PhysFS REQUIRED)
if(DEFINED VCPKG_TARGET_TRIPLET)
  unset(ZLIB_LIBRARY CACHE)
  unset(ZLIB_LIBRARY_DEBUG CACHE)
  unset(ZLIB_LIBRARY_RELEASE CACHE)
endif()
find_package(ZLIB REQUIRED)
find_package(PNG REQUIRED)
find_package(phmap REQUIRED)
find_package(absl CONFIG REQUIRED)
if (TOGGLE_FRAMEWORK_PROTOBUF)
  find_package(Protobuf REQUIRED)
endif()
find_package(LibLZMA REQUIRED)
find_package(LibArchive REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(asio REQUIRED)
find_package(Threads REQUIRED)
find_package(STDUUID CONFIG REQUIRED)
find_package(pugixml CONFIG REQUIRED)
find_package(httplib CONFIG REQUIRED)
find_package(fmt CONFIG REQUIRED)
find_package(spdlog CONFIG REQUIRED)
find_package(utf8cpp REQUIRED)
if(DEFINED VCPKG_TARGET_TRIPLET)
  find_package(unofficial-inih CONFIG REQUIRED)
else()
  pkg_check_modules(INIReader REQUIRED IMPORTED_TARGET INIReader)
  add_library(unofficial::inih::inireader ALIAS PkgConfig::INIReader)
endif()
find_package(Freetype REQUIRED)

if (TARGET spdlog::spdlog)
  set(OTCLIENT_SPDLOG_TARGET spdlog::spdlog)
elseif (TARGET spdlog::spdlog_header_only)
  set(OTCLIENT_SPDLOG_TARGET spdlog::spdlog_header_only)
else()
  message(FATAL_ERROR "spdlog target not found; expected spdlog::spdlog or spdlog::spdlog_header_only")
endif()

if (TARGET fmt::fmt)
  set(OTCLIENT_FMT_TARGET fmt::fmt)
elseif (TARGET fmt::fmt-header-only)
  set(OTCLIENT_FMT_TARGET fmt::fmt-header-only)
else()
  message(FATAL_ERROR "fmt target not found; expected fmt::fmt or fmt::fmt-header-only")
endif()

add_definitions(-DFRAMEWORK_HAVE_LIBARCHIVE)
if(TARGET LibArchive::LibArchive)
  set(LIBARCHIVE_LIBRARY LibArchive::LibArchive)
else()
  include_directories(${LibArchive_INCLUDE_DIRS})
  set(LIBARCHIVE_LIBRARY ${LibArchive_LIBRARIES})
endif()

find_path(CPPCODEC_INCLUDE_DIRS "cppcodec/base32_crockford.hpp")

if(TOGGLE_FRAMEWORK_SOUND)
  if(DEFINED VCPKG_TARGET_TRIPLET)
    find_package(VorbisFile REQUIRED)
    find_package(Vorbis CONFIG REQUIRED)
    find_package(Ogg CONFIG REQUIRED)
  else()
    pkg_check_modules(VORBISFILE REQUIRED vorbisfile)
    add_library(Vorbis::vorbisfile INTERFACE IMPORTED)
    set_target_properties(Vorbis::vorbisfile PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${VORBISFILE_INCLUDE_DIRS}"
      INTERFACE_LINK_LIBRARIES "${VORBISFILE_LIBRARIES}"
    )
    pkg_check_modules(VORBIS REQUIRED vorbis)
    add_library(Vorbis::vorbis INTERFACE IMPORTED)
    set_target_properties(Vorbis::vorbis PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${VORBIS_INCLUDE_DIRS}"
      INTERFACE_LINK_LIBRARIES "${VORBIS_LIBRARIES}"
    )
    pkg_check_modules(OGG REQUIRED ogg)
    add_library(Ogg::ogg INTERFACE IMPORTED)
    set_target_properties(Ogg::ogg PROPERTIES
      INTERFACE_INCLUDE_DIRECTORIES "${OGG_INCLUDE_DIRS}"
      INTERFACE_LINK_LIBRARIES "${OGG_LIBRARIES}"
    )
  endif()
endif()

# Lua is provided by the browser (emscripten) prebuilt port
set(LUA_LIBRARY ${LUA_LIBRARY} ${CMAKE_SOURCE_DIR}/browser/include/lua51/liblua.a)
set(BROWSER_INCLUDE_DIR ${BROWSER_INCLUDE_DIR} ${CMAKE_SOURCE_DIR}/browser/include)

# *****************************************************************************
# OTClient source files configuration
# *****************************************************************************
set(SOURCE_FILES
        framework/core/application.cpp
        framework/core/asyncdispatcher.cpp
        framework/core/binarytree.cpp
        framework/core/clock.cpp
        framework/core/config.cpp
        framework/core/configmanager.cpp
        framework/core/event.cpp
        framework/core/eventdispatcher.cpp
        framework/core/filestream.cpp
        framework/core/logger.cpp
        framework/core/module.cpp
        framework/core/modulemanager.cpp
        framework/core/resourcemanager.cpp
        framework/core/scheduledevent.cpp
        framework/core/unzipper.cpp
        framework/core/unzipper.h
        framework/core/timer.cpp
        framework/luaengine/luaexception.cpp
        framework/luaengine/luainterface.cpp
        framework/luaengine/luaobject.cpp
        framework/luaengine/luavaluecasts.cpp
        framework/luafunctions.cpp
        framework/net/connection.cpp
        framework/net/inputmessage.cpp
        framework/net/outputmessage.cpp
        framework/net/protocol.cpp
        framework/net/protocolhttp.cpp
        framework/net/httplogin.cpp
        framework/net/server.cpp
        framework/html/queryselector.cpp
        framework/html/htmlnode.cpp
        framework/html/htmlparser.cpp
        framework/html/htmlmanager.cpp
        framework/html/cssparser.cpp
        framework/otml/otmldocument.cpp
        framework/otml/otmlemitter.cpp
        framework/otml/otmlexception.cpp
        framework/otml/otmlnode.cpp
        framework/otml/otmlparser.cpp
        framework/platform/platform.cpp
        framework/platform/platformwindow.cpp
        framework/stdext/demangle.cpp
        framework/stdext/math.cpp
        framework/stdext/net.cpp
        framework/stdext/string.cpp
        framework/stdext/time.cpp
        framework/stdext/uri.cpp
        framework/stdext/qrcodegen.cpp
        framework/util/color.cpp
        framework/util/crypt.cpp
        framework/util/stats.cpp
        framework/proxy/proxy.cpp
        framework/proxy/proxy_client.cpp
        framework/net/packet_player.cpp
        framework/net/packet_recorder.cpp

        client/animatedtext.cpp
        client/animator.cpp
        client/attachableobject.cpp
        client/attachedeffect.cpp
        client/attachedeffectmanager.cpp
        client/client.cpp
        client/container.cpp
        client/creature.cpp
        client/creatures.cpp
        client/effect.cpp
        client/game.cpp
        client/gameconfig.cpp
        client/houses.cpp
        client/item.cpp
        client/itemtype.cpp
        client/lightview.cpp
        client/localplayer.cpp
        client/luafunctions.cpp
        client/luavaluecasts_client.cpp
        client/map.cpp
        client/mapio.cpp
        client/mapview.cpp
        client/minimap.cpp
        client/satellitemap.cpp
        client/missile.cpp
        client/outfit.cpp
        client/player.cpp
        client/position.cpp
        client/protocolcodes.cpp
        client/protocolgame.cpp
        client/protocolgameparse.cpp
        client/protocolgamesend.cpp
        client/paperdoll.cpp
        client/paperdollmanager.cpp
        client/spriteappearances.cpp
        client/spritemanager.cpp
        client/statictext.cpp
        client/thing.cpp
        client/thingtype.cpp
        client/thingtypemanager.cpp
        client/tile.cpp
        client/towns.cpp
        client/uicreature.cpp
        client/uigraph.cpp
        client/uiitem.cpp
        client/uieffect.cpp
        client/uimissile.cpp
        client/uimap.cpp
        client/uimapanchorlayout.cpp
        client/uiminimap.cpp
        client/uiprogressrect.cpp
        client/uisprite.cpp
        tools/datdump.cpp
)

if (TOGGLE_FRAMEWORK_GRAPHICS)
  set(SOURCE_FILES ${SOURCE_FILES}
          framework/core/adaptativeframecounter.cpp
          framework/core/graphicalapplication.cpp
          framework/core/garbagecollection.cpp
          framework/input/mouse.cpp
          framework/graphics/animatedtexture.cpp
          framework/graphics/apngloader.cpp
          framework/graphics/bitmapfont.cpp
          framework/graphics/cachedtext.cpp
          framework/graphics/coordsbuffer.cpp
          framework/graphics/textureatlas.cpp
          framework/graphics/drawpool.cpp
          framework/graphics/drawpoolmanager.cpp
          framework/graphics/fontmanager.cpp
          framework/graphics/ttfloader.cpp
          framework/graphics/framebuffer.cpp
          framework/graphics/graphics.cpp
          framework/graphics/image.cpp
          framework/graphics/painter.cpp
          framework/graphics/paintershaderprogram.cpp
          framework/graphics/particle.cpp
          framework/graphics/particleaffector.cpp
          framework/graphics/particleeffect.cpp
          framework/graphics/particleemitter.cpp
          framework/graphics/particlemanager.cpp
          framework/graphics/particlesystem.cpp
          framework/graphics/particletype.cpp
          framework/graphics/shader.cpp
          framework/graphics/shaderprogram.cpp
          framework/graphics/texture.cpp
          framework/graphics/texturemanager.cpp
          framework/graphics/shadermanager.cpp
          framework/ui/uianchorlayout.cpp
          framework/ui/uiboxlayout.cpp
          framework/ui/uigridlayout.cpp
          framework/ui/uihorizontallayout.cpp
          framework/ui/uilayoutflexbox.cpp
          framework/ui/uilayout.cpp
          framework/ui/uimanager.cpp
          framework/ui/uiparticles.cpp
          framework/ui/uitextedit.cpp
          framework/ui/uitranslator.cpp
          framework/ui/uiverticallayout.cpp
          framework/ui/uiwidget.cpp
          framework/ui/uiwidgetbasestyle.cpp
          framework/ui/uiwidgetimage.cpp
          framework/ui/uiwidgettext.cpp
          framework/ui/uiwidgethtml.cpp
          framework/ui/uiqrcode.cpp
  )
endif()

if (TOGGLE_FRAMEWORK_SOUND)
  set(SOURCE_FILES ${SOURCE_FILES}
          framework/sound/combinedsoundsource.cpp
          framework/sound/oggsoundfile.cpp
          framework/sound/soundbuffer.cpp
          framework/sound/soundchannel.cpp
          framework/sound/soundfile.cpp
          framework/sound/soundmanager.cpp
          framework/sound/soundsource.cpp
          framework/sound/streamsoundsource.cpp
          framework/sound/soundeffect.cpp
  )
endif()

if (WASM)
  set(SOURCE_FILES ${SOURCE_FILES}
          framework/platform/browserplatform.cpp
          framework/platform/browserwindow.cpp
          framework/net/webconnection.cpp
  )
endif()

add_library(otclient_core STATIC ${SOURCE_FILES})

target_link_libraries(otclient_core PRIVATE unofficial::inih::inireader)

if(CMAKE_INTERPROCEDURAL_OPTIMIZATION MATCHES "^(ON|1|TRUE)$")
  target_link_options(otclient_core PUBLIC -flto=auto)
endif()

if(TOGGLE_PRE_COMPILED_HEADER)
  # === PRECOMPILED HEADER ===
  target_precompile_headers(otclient_core PRIVATE framework/pch.h)
  target_compile_definitions(otclient_core PRIVATE USE_PRECOMPILED_HEADERS)
  message(STATUS "Use precompiled header: ON")
else()
  message(STATUS "Use precompiled header: OFF")
endif(TOGGLE_PRE_COMPILED_HEADER)

if(SPEED_UP_BUILD_UNITY)
  set_target_properties(otclient_core PROPERTIES UNITY_BUILD ON)
  log_option_enabled("Build unity for speed up compilation")
endif(SPEED_UP_BUILD_UNITY)

target_sources(${PROJECT_NAME} PRIVATE main.cpp)

target_link_libraries(${PROJECT_NAME} PRIVATE otclient_core)

# *****************************************************************************
# Build flags
# *****************************************************************************

if (CMAKE_COMPILER_IS_GNUCXX)
  target_compile_options(otclient_core PRIVATE -Wno-deprecated-declarations)
endif()

if(THREADS_HAVE_PTHREAD_ARG)
  target_compile_options(otclient_core PUBLIC "-pthread")
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Release")
  add_definitions(-DNDEBUG)
endif()

# *****************************************************************************
# Definitions code
# *****************************************************************************

# === ASAN ===
if(ASAN_ENABLED)
  log_option_enabled("asan")

  target_compile_options(otclient_core PUBLIC -fsanitize=address)
  target_link_options(${PROJECT_NAME} PUBLIC -fsanitize=address)
else()
  log_option_disabled("asan")
endif()

# === DEBUG LOG ===
# cmake -DDEBUG_LOG=ON ..
if(CMAKE_BUILD_TYPE MATCHES Debug)
  target_compile_definitions(otclient_core PRIVATE -DDEBUG_LOG=ON )
  log_option_enabled("DEBUG LOG")
else()
  log_option_disabled("DEBUG LOG")
endif(CMAKE_BUILD_TYPE MATCHES Debug)

target_compile_definitions(otclient_core PRIVATE
  OPENSSL_API_COMPAT=0x10100000L
  OPENSSL_SUPPRESS_DEPRECATED
)

# *****************************************************************************
# WebAssembly (Web) build
# *****************************************************************************
option(WASM_USE_WASM_EXCEPTIONS "Use native WebAssembly exception handling" ON)

set(_WASM_LONGJMP_MODE "emscripten")
set(_WASM_EXPORTED_FUNCTIONS "_main,_paste_return,_fullscreen_exit_return")
set(_WASM_CXX_FLAGS "-O3 -ffast-math -frtti -pthread -fexceptions")
if(WASM_USE_WASM_EXCEPTIONS)
  set(_WASM_LONGJMP_MODE "wasm")
  set(_WASM_EXPORTED_FUNCTIONS "${_WASM_EXPORTED_FUNCTIONS},_emscripten_longjmp")
  string(APPEND _WASM_CXX_FLAGS " -fwasm-exceptions")
endif()

target_include_directories(otclient_core
        PUBLIC
        ${CMAKE_SOURCE_DIR}/src
        ${CMAKE_THREAD_LIBS_INIT}
        $<$<BOOL:${TOGGLE_FRAMEWORK_PROTOBUF}>:${Protobuf_INCLUDE_DIRS}>
        ${GMP_INCLUDE_DIR}
        ${PHYSFS_INCLUDE_DIR}
        ${GLEW_INCLUDE_DIR}
        ${PARALLEL_HASHMAP_INCLUDE_DIRS}
        ${NLOHMANN_JSON_INCLUDE_DIR}
        ${OPENSSL_INCLUDE_DIR}
        ${BROWSER_INCLUDE_DIR}
        ${CPPCODEC_INCLUDE_DIRS}
)
target_link_libraries(otclient_core
        PUBLIC
        ${LUA_LIBRARY}
        ${PHYSFS_LIBRARY}
        PNG::PNG
        ${NLOHMANN_JSON_LIBRARY}
        ${GLEW_LIBRARY}
        ${OPENGL_LIBRARIES}
        ${OGG_LIBRARY}
        ${VORBISFILE_LIBRARY}
        ${VORBIS_LIBRARY}
        ${GMP_LIBRARY}
        ${STDUUID}
        ${OPENSSL_LIBRARY}
        ${OPENSSL_CRYPTO_LIBRARY}
        ${HTTPLIB_LIBRARY}
        absl::log_internal_check_op

        Threads::Threads
        asio::asio
        # OpenAL::OpenAL (using emscripten openal api)
        LibLZMA::LibLZMA
        ${LIBARCHIVE_LIBRARY}
        pugixml::pugixml
        ZLIB::ZLIB
        OpenSSL::SSL
        OpenSSL::Crypto
        httplib::httplib
        ${OTCLIENT_FMT_TARGET}
        ${OTCLIENT_SPDLOG_TARGET}
        utf8cpp::utf8cpp
        Ogg::ogg
        Vorbis::vorbisfile
        Vorbis::vorbis
        Freetype::Freetype
)

if (TOGGLE_FRAMEWORK_PROTOBUF)
    target_link_libraries(otclient_core
        PUBLIC
        protobuf::libprotobuf protobuf
    )
endif()


if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  target_compile_options(otclient_core
          PRIVATE
          -Wall -Wextra -Wpedantic
  )
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g")
endif()

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${_WASM_CXX_FLAGS}")

set(WASM_LINK_OPTIONS
        -sINVOKE_RUN=0
        -sEXIT_RUNTIME=1
        -sTEXTDECODER=2
        -sCASE_INSENSITIVE_FS=1
        -lopenal
        -lidbfs.js
        -lwebsocket.js
        -sEXPORTED_RUNTIME_METHODS=ccall
        "-sEXPORTED_FUNCTIONS=${_WASM_EXPORTED_FUNCTIONS}"
        -sINCOMING_MODULE_JS_API=[locateFile,preRun,postRun,print,printErr,canvas,setStatus,monitorRunDependencies]
        -sFORCE_FILESYSTEM
        -sMALLOC=dlmalloc
        "-sSUPPORT_LONGJMP=${_WASM_LONGJMP_MODE}"
        -sWEBSOCKET_SUBPROTOCOL=binary
        -sOFFSCREENCANVAS_SUPPORT=1
        -sOFFSCREEN_FRAMEBUFFER
        -sENVIRONMENT=web,worker
        -sPROXY_TO_PTHREAD
        -sFULL_ES2=1
        -sMIN_WEBGL_VERSION=2
        -sMAX_WEBGL_VERSION=2
        -sUSE_PTHREADS=1
        -sFETCH=1
        -sPTHREAD_POOL_SIZE=navigator.hardwareConcurrency
        # Growable WASM memory becomes a resizable SharedArrayBuffer, which
        # Chrome 149+ refuses to accept as a source for WebGL uploads
        # ("ArrayBuffer value must not be resizable"). Use a fixed heap.
        -sALLOW_MEMORY_GROWTH=0
        -sINITIAL_MEMORY=1073741824
        --preload-file=../otclientrc.lua@otclientrc.lua
        --preload-file=../../init.lua@init.lua
        --preload-file=../../config.ini@config.ini
        --preload-file=../../data/cursors@data/cursors
        --preload-file=../../data/fonts@data/fonts
        --preload-file=../../data/images@data/images
        --preload-file=../../data/json@data/json
        --preload-file=../../data/locales@data/locales
        --preload-file=../../data/particles@data/particles
        --preload-file=../../data/sounds@data/sounds
        --preload-file=../../data/styles@data/styles
        --preload-file=../../data/setup.otml@data/setup.otml
        --preload-file=../../data/things/1525/Tibia.dat@data/things/1525/Tibia.dat
        --preload-file=../../data/things/1525/appearances.dat@data/things/1525/appearances.dat
        --preload-file=../../data/things/1525/appearancesassets.json.sha256@data/things/1525/appearancesassets.json.sha256
        --preload-file=../../data/things/1525/catalog-content.json@data/things/1525/catalog-content.json
        --preload-file=../../data/things/1525/staticdata-0bd51e1660f9d58594eb10000c35ea51113fc668aa3ee416c8c6b7ebb59b78ff.dat@data/things/1525/staticdata-0bd51e1660f9d58594eb10000c35ea51113fc668aa3ee416c8c6b7ebb59b78ff.dat
        --preload-file=../../data/things/1525/proficiencies-1a915dffd9265cd1c18d39e55da7ede691b2e58add534bc186238ae028a73f22.json@data/things/1525/proficiencies-1a915dffd9265cd1c18d39e55da7ede691b2e58add534bc186238ae028a73f22.json
        --preload-file=../../modules@modules
        --shell-file=../browser/shell.html
        --use-preload-cache
)

if(WASM_USE_WASM_EXCEPTIONS)
  list(APPEND WASM_LINK_OPTIONS "-sDEFAULT_LIBRARY_FUNCS_TO_INCLUDE=['emscripten_longjmp']")
endif()

if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  list(APPEND WASM_LINK_OPTIONS -sASSERTIONS=1)
endif()

target_link_options(${PROJECT_NAME} PRIVATE ${WASM_LINK_OPTIONS})
string(REPLACE ";" " " _WASM_LINK_LOG "${WASM_LINK_OPTIONS}")
message(STATUS "WASM link options: ${_WASM_LINK_LOG}")

# Track Lua/OTUI/OTMOD assets so ninja only relinks (re-embeds the preloaded
# data) when they change, without recompiling any C++.
set(_LUA_PRELOAD_ROOT "${CMAKE_SOURCE_DIR}/..")
file(GLOB_RECURSE _LUA_PRELOAD_FILES
        "${_LUA_PRELOAD_ROOT}/otclientrc.lua"
        "${_LUA_PRELOAD_ROOT}/init.lua"
        "${_LUA_PRELOAD_ROOT}/modules/*.lua"
        "${_LUA_PRELOAD_ROOT}/modules/*.otui"
        "${_LUA_PRELOAD_ROOT}/modules/*.otmod"
        "${_LUA_PRELOAD_ROOT}/data/*.lua"
        "${_LUA_PRELOAD_ROOT}/data/*.otui"
        "${_LUA_PRELOAD_ROOT}/data/*.otmod"
        "${_LUA_PRELOAD_ROOT}/data/setup.otml"
        "${_LUA_PRELOAD_ROOT}/data/things/*.dat"
        "${_LUA_PRELOAD_ROOT}/data/things/*/*.dat"
        "${_LUA_PRELOAD_ROOT}/data/things/*/*.json"
        "${_LUA_PRELOAD_ROOT}/data/things/*/*.json.sha256"
        "${_LUA_PRELOAD_ROOT}/data/things/*/catalog-content.json"
        "${_LUA_PRELOAD_ROOT}/data/sounds/*/catalog-sound.json"
        "${_LUA_PRELOAD_ROOT}/config.ini"
        "${CMAKE_SOURCE_DIR}/browser/shell.html"
)
if(_LUA_PRELOAD_FILES)
    set_target_properties(${PROJECT_NAME} PROPERTIES LINK_DEPENDS "${_LUA_PRELOAD_FILES}")
endif()
set(CMAKE_EXECUTABLE_SUFFIX ".html")
set(VCPKG_TARGET_TRIPLET "wasm32-emscripten" CACHE STRING "")

# *****************************************************************************
# Link compilation files folder
# *****************************************************************************

## Link compilation files to build/bin folder, else link to the main dir
if (TOGGLE_BIN_FOLDER)
  set_target_properties(${PROJECT_NAME}
          PROPERTIES
          RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
  )
else()
  set_target_properties(${PROJECT_NAME}
          PROPERTIES
          RUNTIME_OUTPUT_DIRECTORY "${CMAKE_SOURCE_DIR}/"
  )
endif()