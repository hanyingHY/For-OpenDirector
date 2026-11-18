"""Attach the DPAPI ticket only to the authenticated service for this launch."""
import hashlib
import hmac
import os
from uuid import uuid4

import httpx
from opendirector import cli

record = os.environ.pop('OD_LOCAL_TICKET', '').split('\n')
port = int(record[0]) if len(record) == 2 and record[0].isdigit() else 0
origin = f'http://127.0.0.1:{port}'
if 0 < port <= 65535:
    os.environ.setdefault('OPENDIRECTOR_API_URL', origin)


class DesktopClient(cli.Client):
    def __init__(self, project, url, session, operation_id):
        super().__init__(project, url, session, operation_id)
        if port and self.http.base_url == httpx.URL(origin):
            nonce = uuid4().hex
            proof = self.http.get('/__desktop/probe/'+nonce).text
            if not hmac.compare_digest(proof.encode(), hmac.new(record[1].encode(), nonce.encode(), hashlib.sha256).hexdigest().encode()):
                raise RuntimeError('Restart OpenDirector / 请重新启动 OpenDirector')
            def authorize(request):
                if (request.url.scheme, request.url.host, request.url.port) == ('http', '127.0.0.1', port):
                    request.headers['X-OpenDirector-Desktop'] = record[1]
            self.http.event_hooks['request'].append(authorize)


cli.Client = DesktopClient
cli.main()
