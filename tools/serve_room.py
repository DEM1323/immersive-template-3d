"""Local static + WebSocket sync server for Ephemeral Jeopardy HTML5 room exports.

Serves exports/web/ (walls.html, floor.html, index.html, index.wasm, index.pck, ...)
AND relays real-time WebSocket sync frames on /ws on the exact same port so two
independent browsers/profiles on the same PC (or across LAN) stay tightly synced
just by pasting two URLs:
  - 4 Walls: http://127.0.0.1:8080/walls.html
  - Floor:   http://127.0.0.1:8080/floor.html
"""

from __future__ import annotations

import argparse
import asyncio
import mimetypes
from pathlib import Path
from typing import Set

from aiohttp import WSMsgType, web

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/javascript", ".js")


def create_app(web_root: Path) -> web.Application:
    app = web.Application()
    clients: Set[web.WebSocketResponse] = set()

    async def ws_handler(request: web.Request) -> web.WebSocketResponse:
        ws = web.WebSocketResponse(heartbeat=20.0)
        await ws.prepare(request)
        clients.add(ws)
        try:
            async for msg in ws:
                if msg.type == WSMsgType.TEXT:
                    stale = []
                    for peer in list(clients):
                        if peer is ws or peer.closed:
                            continue
                        try:
                            await peer.send_str(msg.data)
                        except Exception:
                            stale.append(peer)
                    for peer in stale:
                        clients.discard(peer)
                elif msg.type == WSMsgType.ERROR:
                    break
        finally:
            clients.discard(ws)
        return ws

    async def root_redirect(_request: web.Request) -> web.StreamResponse:
        return web.FileResponse(web_root / "index.html")

    async def file_handler(request: web.Request) -> web.StreamResponse:
        rel = request.match_info.get("path", "index.html") or "index.html"
        target = (web_root / rel).resolve()
        try:
            target.relative_to(web_root.resolve())
        except ValueError:
            raise web.HTTPForbidden()
        if not target.is_file():
            raise web.HTTPNotFound()
        resp = web.FileResponse(target)
        # Prevent stale HTML caching across re-exports while allowing WASM/PCK speed
        if target.suffix.lower() in {".html", ".js"}:
            resp.headers["Cache-Control"] = "no-cache"
        return resp

    app.router.add_get("/ws", ws_handler)
    app.router.add_get("/", root_redirect)
    app.router.add_get("/{path:.*}", file_handler)
    return app


def main() -> None:
    parser = argparse.ArgumentParser(description="Serve Ephemeral Jeopardy HTML5 + WebSocket room sync.")
    parser.add_argument("--host", default="0.0.0.0", help="Bind host (default 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080, help="HTTP + WebSocket port (default 8080)")
    parser.add_argument(
        "--dir",
        default=str(Path(__file__).resolve().parent.parent / "exports" / "web"),
        help="Path to exported web directory",
    )
    args = parser.parse_args()

    web_root = Path(args.dir).resolve()
    if not (web_root / "index.html").is_file():
        raise SystemExit(f"Web export not found at {web_root}. Run '.\\tools\\godot_dev.ps1 export-web' first.")

    print("=" * 64)
    print("  Ephemeral Jeopardy — Local HTML5 + Room Sync Server")
    print("=" * 64)
    print(f"  Left Wall URL       : http://127.0.0.1:{args.port}/left.html")
    print(f"  Center Wall (Host)  : http://127.0.0.1:{args.port}/center.html")
    print(f"  Right Wall URL      : http://127.0.0.1:{args.port}/right.html")
    print(f"  Back Wall URL       : http://127.0.0.1:{args.port}/back.html")
    print(f"  Floor URL           : http://127.0.0.1:{args.port}/floor.html")
    print("-" * 64)
    print(f"  4-Wall Strip URL    : http://127.0.0.1:{args.port}/walls.html")
    print(f"  All-5 Combined URL  : http://127.0.0.1:{args.port}/index.html")
    print(f"  WebSocket Relay     : ws://127.0.0.1:{args.port}/ws")
    print("=" * 64)
    print("Press Ctrl+C to stop.")

    app = create_app(web_root)
    web.run_app(app, host=args.host, port=args.port, print=None)


if __name__ == "__main__":
    main()
