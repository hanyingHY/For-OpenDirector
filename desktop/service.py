"""Private desktop transport around the unmodified OpenDirector ASGI app."""
import asyncio
import hmac
import os
import socket
import sys
import threading

PORT = 48765  # stable WebView origin keeps IndexedDB and localStorage on upgrades
HOST = f'127.0.0.1:{PORT}'
ORIGIN = 'http://' + HOST


class DesktopSession:
    def __init__(self, app, token):
        self.app = app
        self.token = token

    async def __call__(self, scope, receive, send):
        if scope['type'] == 'http':
            headers = dict(scope['headers'])
            if (headers.get(b'host') != HOST.encode() or
                headers.get(b'origin', ORIGIN.encode()) != ORIGIN.encode() or
                not hmac.compare_digest(headers.get(b'x-opendirector-desktop', b''), self.token)):
                await send({'type': 'http.response.start', 'status': 403, 'headers': []})
                await send({'type': 'http.response.body', 'body': b'Private desktop session'})
                return
        await self.app(scope, receive, send)


def main():
    token = sys.stdin.buffer.readline().strip()
    if len(token) != 44: raise RuntimeError('Desktop handshake missing')
    import uvicorn
    from opendirector_api.main import create_app
    with socket.socket() as listener:
        if os.name == 'nt': listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        listener.bind(('127.0.0.1', PORT))
        class Service(uvicorn.Server):
            async def startup(self, sockets=None):
                await super().startup(sockets=sockets)
                if self.started:
                    print('OD-DESKTOP-READY', flush=True)

        server = Service(uvicorn.Config(DesktopSession(create_app(), token), log_level='warning', access_log=False, proxy_headers=False))
        def stop():
            sys.stdin.buffer.readline()  # shutdown message or host pipe closed
            server.should_exit = True
        threading.Thread(target=stop, daemon=True).start()
        asyncio.run(server.serve(sockets=[listener]))

if __name__ == '__main__': main()
