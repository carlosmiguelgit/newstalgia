#!/usr/bin/env python3
"""Servidor web OTClient + proxy WebSocket->TCP + abertura automatica do navegador.

O cliente WebAssembly usa pthreads e SharedArrayBuffer, entao o servidor
precisa responder com:
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp

O client web se conecta ao game server via WebSocket (browser nao faz TCP cru).
O crystalserver fala TCP puro, entao um proxy WebSocket->TCP e iniciado junto.

Uso:
  python serve_web.py [porta-web] [porta-websocket] [porta-tcp-destino]

Ao rodar, tudo sobe junto (site + proxy) e o navegador abre sozinho.
"""
import argparse
import asyncio
import os
import socket
import sys
import threading
import webbrowser
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer

import websockets

ROOT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_BUILD_DIR = os.path.join(ROOT_DIR, "engine", "build-emscripten-web", "bin")

TCP_HOST = "127.0.0.1"

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".data": "application/octet-stream",
    ".json": "application/json",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".css": "text/css; charset=utf-8",
    ".map": "application/json",
}


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=BUILD_DIR, **kwargs)

    def translate_path(self, path):
        path = path.split("?", 1)[0].split("#", 1)[0]
        import urllib.parse
        path = urllib.parse.unquote(path)
        import posixpath
        path = posixpath.normpath(path)
        words = path.split("/")
        words = list(filter(None, words))
        # Serve data/ from project root (for Tibia.spr etc.)
        if words and words[0] == "data":
            directory = ROOT_DIR
        else:
            directory = BUILD_DIR
        for word in words:
            drive, word = os.path.splitdrive(word)
            head, word = os.path.split(word)
            if word in (os.curdir, os.pardir, ""):
                continue
            directory = os.path.join(directory, word)
        return directory

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def guess_type(self, path):
        ext = os.path.splitext(path)[1].lower()
        return MIME.get(ext, "application/octet-stream")

    def do_POST(self):
        # Endpoint que recebe os logs do client (rota /log) e imprime no terminal
        path = self.path.split("?", 1)[0].split("#", 1)[0].rstrip("/")
        if path != "/log":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(length).decode("utf-8", errors="replace") if length else ""
        for line in body.splitlines():
            print("  [client] %s" % line)
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, fmt, *args):
        sys.stderr.write("[%s] %s\n" % (self.address_string(), fmt % args))


# ---------------------------------------------------------------------------
# Proxy WebSocket -> TCP (encaminha o protocolo OTS para o crystalserver)
# ---------------------------------------------------------------------------

async def _bridge(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, ws):
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            await ws.send(data)
    except Exception:
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def _ws_handler(ws, tcp_port):
    try:
        tcp_reader, tcp_writer = await asyncio.open_connection(TCP_HOST, tcp_port)
    except Exception as e:
        print("  [proxy] TCP %s:%d nao conectou: %s" % (TCP_HOST, tcp_port, e))
        return

    forward_task = asyncio.create_task(_bridge(tcp_reader, tcp_writer, ws))
    try:
        async for message in ws:
            if message is None:
                break
            if isinstance(message, str):
                message = message.encode()
            tcp_writer.write(message)
            await tcp_writer.drain()
    except Exception:
        pass
    finally:
        forward_task.cancel()
        try:
            await forward_task
        except Exception:
            pass
        try:
            tcp_writer.close()
        except Exception:
            pass
        try:
            await ws.close()
        except Exception:
            pass


async def _run_proxy(ws_port, tcp_port):
    async with websockets.serve(
        lambda ws: _ws_handler(ws, tcp_port),
        "0.0.0.0",
        ws_port,
        subprotocols=["binary"],
        ping_interval=20,
    ):
        await asyncio.Future()


def start_proxy(ws_port, tcp_port):
    """Inicia o proxy WebSocket->TCP numa thread com seu proprio event loop."""
    loop = asyncio.new_event_loop()
    threading.Thread(
        target=lambda: loop.run_until_complete(_run_proxy(ws_port, tcp_port)),
        daemon=True,
    ).start()
    return loop


# ---------------------------------------------------------------------------
# Servidor web
# ---------------------------------------------------------------------------

def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return "127.0.0.1"


def main():
    global BUILD_DIR
    parser = argparse.ArgumentParser(description="Servidor web OTClient + proxy")
    parser.add_argument("port", nargs="?", type=int, default=8000,
                        help="porta do servidor web (default: 8000)")
    parser.add_argument("ws_port", nargs="?", type=int, default=8081,
                        help="porta do proxy websocket (default: 8081)")
    parser.add_argument("tcp_port", nargs="?", type=int, default=7172,
                        help="porta TCP do game server (default: 7172)")
    parser.add_argument("build_dir", nargs="?", default=DEFAULT_BUILD_DIR)
    args = parser.parse_args()

    BUILD_DIR = os.path.abspath(args.build_dir)
    if not os.path.isdir(BUILD_DIR):
        sys.stderr.write("Diretorio de build nao encontrado: %s\n" % BUILD_DIR)
        sys.exit(1)

    if not os.path.isfile(os.path.join(BUILD_DIR, "otclient.html")):
        sys.stderr.write("otclient.html nao encontrado em %s\n" % BUILD_DIR)
        sys.exit(1)

    # Subindo o proxy
    try:
        start_proxy(args.ws_port, args.tcp_port)
    except Exception as e:
        print("  AVISO: nao foi possivel iniciar o proxy websocket: %s" % e)
        print("  (pip install websockets)")

    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    url = "http://%s:%d/otclient.html" % (lan_ip(), args.port)
    local = "http://localhost:%d/otclient.html" % args.port
    print("=" * 60)
    print("OTClient web no ar!")
    print("  Local:    %s" % local)
    print("  Rede:     %s" % url)
    print("  Build:    %s" % BUILD_DIR)
    print("  Proxy:    ws://0.0.0.0:%d -> tcp %s:%d" % (args.ws_port, TCP_HOST, args.tcp_port))
    print("  Abrindo o navegador...")
    print("  Ctrl+C para parar.")
    print("=" * 60)

    threading.Timer(0.8, lambda: webbrowser.open(local)).start()

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()