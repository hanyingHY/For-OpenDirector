"""Adapt only the desktop CLI transport. Never attach the ticket to a remote URL."""
import os
from opendirector import cli

ORIGIN = 'http://127.0.0.1:48765'
ticket = os.environ.pop('OD_LOCAL_TICKET', None)
if ticket:
    os.environ.setdefault('OPENDIRECTOR_API_URL', ORIGIN)


class DesktopClient(cli.Client):
    def __init__(self, project, url, session, operation_id):
        super().__init__(project, url, session, operation_id)
        def authorize(request):
            if ticket and (request.url.scheme, request.url.host, request.url.port) == ('http', '127.0.0.1', 48765):
                request.headers['X-OpenDirector-Desktop'] = ticket
        self.http.event_hooks['request'].append(authorize)


cli.Client = DesktopClient
cli.main()
