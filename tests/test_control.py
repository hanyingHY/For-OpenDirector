"""A desktop child must not wait for, consume, or inherit the host's shutdown signal."""
from pathlib import Path
import subprocess
import sys
import unittest


class StdinBoundary(unittest.TestCase):
    def test_child_gets_eof_while_private_shutdown_pipe_stays_live(self):
        script = '''from desktop.service import detach_control
import sys,subprocess
control=detach_control()
subprocess.run([sys.executable,'-c',"import sys; assert sys.stdin.buffer.read()==b''"],check=True,timeout=5)
print('READY',flush=True)
assert control.readline()==b'shutdown\\n'
'''
        # Keep the pipe open while the grandchild reads. A mere communicate()
        # would close it immediately and hide the Windows first-turn regression.
        with subprocess.Popen([sys.executable,'-c',script],cwd=Path(__file__).resolve().parents[1],
                              stdin=subprocess.PIPE,stdout=subprocess.PIPE) as host:
            try:
                self.assertEqual(host.stdout.readline().strip(), b'READY')
                host.stdin.write(b'shutdown\n'); host.stdin.flush()
                self.assertEqual(host.wait(timeout=5), 0)
            finally:
                if host.poll() is None: host.kill()
