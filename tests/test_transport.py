"""Transport-only checks; the Windows workflows cover the actual PE and GUI."""
import unittest
from desktop.service import DesktopSession, HOST, ORIGIN


class TransportTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.calls, self.responses = [], []
        async def inner(scope, receive, send):
            self.calls.append(scope['type'])
        self.session = DesktopSession(inner, b'secret')

    async def send(self, message):
        self.responses.append(message)

    async def dispatch(self, **headers):
        scope = {'type': 'http', 'headers': [(k.encode(), v.encode()) for k, v in headers.items()]}
        await self.session(scope, None, self.send)

    async def test_local_header_is_not_authentication(self):
        await self.dispatch(host=HOST, **{'x-opendirector-request': '1'})
        self.assertEqual(self.responses[0]['status'], 403)
        self.assertFalse(self.calls)

    async def test_reject_other_hosts_and_origins(self):
        for host, origin in [('example.org', ORIGIN), (HOST, 'http://127.0.0.1:8080'), (HOST, 'null')]:
            with self.subTest(host=host, origin=origin):
                self.responses.clear()
                await self.dispatch(host=host, origin=origin, **{'x-opendirector-desktop': 'secret'})
                self.assertEqual(self.responses[0]['status'], 403)
                self.assertFalse(self.calls)

    async def test_authenticated_same_origin(self):
        await self.dispatch(host=HOST, origin=ORIGIN, **{'x-opendirector-desktop': 'secret'})
        self.assertEqual(self.calls, ['http'])

    async def test_lifespan_is_owned_by_upstream(self):
        await self.session({'type': 'lifespan'}, None, self.send)
        self.assertEqual(self.calls, ['lifespan'])
