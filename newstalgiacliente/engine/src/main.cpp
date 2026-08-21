/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "client/client.h"
#include "client/gameconfig.h"
#include "framework/core/graphicalapplication.h"
#include "framework/core/resourcemanager.h"
#include "framework/luaengine/luainterface.h"
#include "framework/platform/platform.h"
#ifdef FRAMEWORK_EDITOR
#include "tools/datdump.h"
#endif
#include <iostream>
#include <ctime>

#ifdef FRAMEWORK_NET
#include <framework/net/protocolhttp.h>
#endif

namespace {

bool shouldShowHelp(const std::vector<std::string>& args)
{
    for (const auto& arg : args) {
        if (arg == "--help" || arg == "-h" || arg == "/?")
            return true;
    }
    return false;
}

std::string parseUserDir(const std::vector<std::string>& args)
{
    static const std::string prefix = "--user-dir=";
    for (const auto& arg : args) {
        if (arg.starts_with(prefix))
            return arg.substr(prefix.size());
    }
    return {};
}

void printHelp(const std::string& executableName)
{
    std::cout << "Usage: " << executableName << " [options]\n\n"
                 "General options:\n"
                 "  --help, -h, /?              Show this help message and exit\n"
                 "  --user-dir=<path>           Use <path> for configs/profiles instead of the default user dir\n"
                 "  --encrypt <password>        Encrypt assets (requires ENABLE_ENCRYPTION == 1 && ENABLE_ENCRYPTION_BUILDER == 1 build)\n\n"
                 "DAT debugging:\n"
                 "  --dump-dat-to-json=<path|ver> Dump the specified Tibia DAT file or version as JSON (requires FRAMEWORK_EDITOR build)\n"
                 "    --dump-dat-output=<path>    Write JSON to file instead of stdout\n"
                 "    --dump-dat-compact          Emit compact (single-line) JSON\n";
}

std::string buildStartupTimestamp()
{
    std::time_t now = std::time(nullptr);
    std::tm localTime{};
    localtime_r(&now, &localTime);

    char buffer[64];
    if (std::strftime(buffer, sizeof(buffer), "%b %d %Y %H:%M:%S", &localTime) == 0) {
        return "unknown";
    }

    return buffer;
}

} // namespace

int main(const int argc, const char* argv[])
{
    std::vector<std::string> args(argv, argv + argc);
    g_logger.info("Application started at {}", buildStartupTimestamp());

    // process args encoding
    g_platform.init(args);

    // initialize resources
    g_resources.init(args[0].data());

    // a --user-dir override isolates all persisted state (configs, remember
    // password, bot profiles) under a caller-chosen dir; set before init.lua
    // resolves the write dir via setupUserWriteDir. see #1540
    if (const auto userDir = parseUserDir(args); !userDir.empty()) {
        g_resources.setUserDirOverride(userDir);
    }

#if ENABLE_ENCRYPTION == 1 && ENABLE_ENCRYPTION_BUILDER == 1
    if (std::find(args.begin(), args.end(), "--encrypt") != args.end()) {
        g_lua.init();
        g_resources.runEncryption(args.size() >= 3 ? args[2] : std::string(ENCRYPTION_PASSWORD));
        g_logger.info("Encryption complete");
        return 0;
    }
#endif

    if (g_resources.launchCorrect(args)) {
        return 0; // started other executable
    }

    // find script init.lua and run it
    if (!g_resources.discoverWorkDir("init.lua"))
        g_logger.fatal("Unable to find work directory, the application cannot be initialized.");

    if (shouldShowHelp(args)) {
        printHelp(args[0]);
        return 0;
    }

#ifdef FRAMEWORK_EDITOR
    if (const auto dumpRequest = datdump::parseRequest(args); dumpRequest) {
        return datdump::run(*dumpRequest) ? 0 : 1;
    }
#endif

    // initialize application framework and otclient
    const auto drawEvents = ApplicationDrawEventsPtr(&g_client, [](ApplicationDrawEvents*) {});
    g_app.init(args, new GraphicalApplicationContext(g_gameConfig.getSpriteSize(), drawEvents));

    g_client.init(args);
#ifdef FRAMEWORK_NET
    g_http.init();
#endif

    if (!g_lua.safeRunScript("init.lua"))
        g_logger.fatal("Unable to run script init.lua!");

    // the run application main loop
    g_app.run();

    // unload modules
    g_app.deinit();

    // terminate everything and free memory
    g_client.terminate();
    g_app.terminate();
#ifdef FRAMEWORK_NET
    g_http.terminate();
#endif
    return 0;
}
