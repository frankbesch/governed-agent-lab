#!/usr/bin/env python3
"""Loopback TCP forwarder: 127.0.0.1:4100 -> 127.0.0.1:4000 (LiteLLM).
Why: NemoClaw reserves port 4000 for its own Model Router, so the sandbox reaches LiteLLM on 4100
through host.openshell.internal (Lima maps 192.168.5.2 to the Mac's loopback). Binds loopback only."""
import asyncio

LISTEN, TARGET = ("127.0.0.1", 4100), ("127.0.0.1", 4000)


async def pipe(r, w):
    try:
        while data := await r.read(65536):
            w.write(data)
            await w.drain()
    except (ConnectionError, asyncio.CancelledError):
        pass
    finally:
        w.close()


async def handle(cr, cw):
    try:
        tr, tw = await asyncio.open_connection(*TARGET)
    except OSError:
        cw.close()
        return
    await asyncio.gather(pipe(cr, tw), pipe(tr, cw))


async def main():
    srv = await asyncio.start_server(handle, *LISTEN)
    print(f"forwarding {LISTEN} -> {TARGET}", flush=True)
    async with srv:
        await srv.serve_forever()

asyncio.run(main())
