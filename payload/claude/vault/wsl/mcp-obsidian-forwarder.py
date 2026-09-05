#!/usr/bin/env python3
"""
TCP forwarder: bridges 127.0.0.1:LISTEN_PORT inside WSL to TARGET_HOST:TARGET_PORT.

Why this exists: mcp-obsidian hardcodes host='127.0.0.1' and ignores
OBSIDIAN_HOST, and under WSL2 NAT networking WSL's loopback is not Windows'
loopback. Windows is only reachable at the gateway IP, so this forwarder
makes 127.0.0.1:27124 inside WSL land on <gateway>:27124.

It only works if Obsidian's Local REST API plugin binds to 0.0.0.0 (its
default, 127.0.0.1, is invisible from WSL) and Windows Firewall allows
inbound TCP 27124. See mcp-obsidian-wrapper.sh for the exact settings.

TLS is opaque to TCP forwarding; mcp-obsidian uses verify_ssl=False, so
the cert mismatch (cert is for the Windows IP, not 127.0.0.1) is fine.
"""

import asyncio
import os
import signal
import sys


async def pipe(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    try:
        while True:
            data = await reader.read(65536)
            if not data:
                break
            writer.write(data)
            await writer.drain()
    except (ConnectionResetError, BrokenPipeError, asyncio.IncompleteReadError):
        pass
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def handle_client(
    client_reader: asyncio.StreamReader,
    client_writer: asyncio.StreamWriter,
    target_host: str,
    target_port: int,
) -> None:
    try:
        target_reader, target_writer = await asyncio.open_connection(target_host, target_port)
    except OSError as e:
        print(f"forwarder: connect to {target_host}:{target_port} failed: {e}", file=sys.stderr)
        client_writer.close()
        return
    await asyncio.gather(
        pipe(client_reader, target_writer),
        pipe(target_reader, client_writer),
    )


async def main() -> None:
    listen_host = os.environ.get("FORWARDER_LISTEN_HOST", "127.0.0.1")
    listen_port = int(os.environ.get("FORWARDER_LISTEN_PORT", "27124"))
    target_host = os.environ["FORWARDER_TARGET_HOST"]
    target_port = int(os.environ.get("FORWARDER_TARGET_PORT", "27124"))

    server = await asyncio.start_server(
        lambda r, w: handle_client(r, w, target_host, target_port),
        listen_host,
        listen_port,
        reuse_address=True,
    )
    print(
        f"forwarder: listening on {listen_host}:{listen_port} -> {target_host}:{target_port}",
        file=sys.stderr,
    )

    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, stop.set)

    async with server:
        serve_task = asyncio.create_task(server.serve_forever())
        await stop.wait()
        serve_task.cancel()


if __name__ == "__main__":
    asyncio.run(main())
