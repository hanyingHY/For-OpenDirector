"""Windows x64 stable-channel updater. No renderer IPC, credentials or user-supplied URLs."""
import argparse
import hashlib
from importlib.resources import files
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from urllib.parse import urlsplit
from urllib.request import build_opener, HTTPRedirectHandler, Request

REPO = 'hanyingHY/For-OpenDirector'
FEED = f'https://api.github.com/repos/{REPO}/releases?per_page=100'
MANIFEST = 'windows-update.json'
BUNDLE = MANIFEST + '.sigstore.json'
MAX_EXE = 512 * 1024 * 1024
VERSION = re.compile(r'(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})-desktop\.(0|[1-9][0-9]{0,5})')


def number(version):
    match = VERSION.fullmatch(version)
    if not match:
        raise ValueError('Invalid Windows release version')
    return tuple(map(int, match.groups()))


def installer_name(version):
    number(version)
    return f'OpenDirector-{version}-x64-Setup.exe'


def select(releases, installed):
    current = number(installed)
    eligible = []
    for release in releases:
        if release.get('draft') is not False or release.get('prerelease') is not False:
            continue
        tag = release['tag_name']
        version = tag.removeprefix('windows-x64-')
        if version != tag and VERSION.fullmatch(version) and number(version) > current:
            eligible.append(version)
    return max(eligible, key=number, default=None)


class GithubRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        u = urlsplit(newurl)
        if u.scheme != 'https' or u.netloc not in ('github.com', 'api.github.com', 'release-assets.githubusercontent.com', 'objects.githubusercontent.com'):
            raise ValueError('Untrusted update redirect')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def fetch(url):
    req = Request(url, headers={'User-Agent': 'OpenDirector-Windows-Update/1'})
    return build_opener(GithubRedirect()).open(req, timeout=30)


def small(open_url, url, limit):
    with open_url(url) as stream:
        data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError('Update metadata too large')
    return data


def authenticate(data, proof):
    from sigstore.models import Bundle, TrustedRoot
    from sigstore.verify import Verifier, policy
    # Trust roots ship with the installed verifier, never with the downloaded file.
    root = files('sigstore._store') / 'https%3A%2F%2Ftuf-repo-cdn.sigstore.dev' / 'trusted_root.json'
    workflow = f'https://github.com/{REPO}/.github/workflows/windows.yml@refs/heads/'
    signer = policy.AnyOf([policy.Identity(identity=workflow + branch, issuer='https://token.actions.githubusercontent.com')
                           for branch in ('main', 'arena/634b6979-for-opendirector')])
    Verifier(trusted_root=TrustedRoot.from_file(str(root))).verify_artifact(data, Bundle.from_json(proof), signer)


def metadata(data, proof, version, verify):
    verify(data, proof)
    m = json.loads(data)
    if (m['schema'] != 1 or m['channel'] != 'windows-x64-stable' or m['version'] != version or
            m['file'] != installer_name(version) or not re.fullmatch('[a-f0-9]{64}', m['sha256']) or
            type(m['size']) is not int or not 0 < m['size'] <= MAX_EXE):
        raise ValueError('Wrong update version, target or digest')
    return m


def matches(stream, m):
    return os.fstat(stream.fileno()).st_size == m['size'] and hashlib.file_digest(stream, 'sha256').hexdigest() == m['sha256']


def stage(installed, cache, open_url=fetch, verify=authenticate):
    version = select(json.loads(small(open_url, FEED, 4*1024*1024)), installed)
    if version is None:
        return None
    base = f'https://github.com/{REPO}/releases/download/windows-x64-{version}/'
    data = small(open_url, base + MANIFEST, 8192)
    proof = small(open_url, base + BUNDLE, 128*1024)
    m = metadata(data, proof, version, verify)
    dest = cache / version
    dest.mkdir(parents=True, exist_ok=True)
    exe = dest / m['file']
    for partial in dest.glob('*.part'):
        partial.unlink(missing_ok=True)
    valid = False
    if exe.is_file():
        with exe.open('rb') as existing:
            valid = matches(existing, m)
    if not valid:
        temp = dest / (m['file'] + '.part')
        try:
            digest, total = hashlib.sha256(), 0
            with open_url(base + m['file']) as source, temp.open('xb') as target:
                while chunk := source.read(1024*1024):
                    total += len(chunk)
                    if total > m['size']:
                        raise ValueError('Update exceeds signed size')
                    target.write(chunk)
                    digest.update(chunk)
            if total != m['size'] or digest.hexdigest() != m['sha256']:
                raise ValueError('Incomplete or damaged update; retry download')
            temp.replace(exe)
        finally:
            temp.unlink(missing_ok=True)
    for name, contents in [(MANIFEST, data), (BUNDLE, proof)]:
        part = dest / (name+'.part')
        part.write_bytes(contents)
        part.replace(dest / name)
    return version


def read_locked(path):
    """Deny writes and deletion between the final hash check and CreateProcess."""
    import ctypes as c
    import msvcrt
    from ctypes import wintypes as w
    kernel = c.WinDLL('kernel32', use_last_error=True)
    kernel.CreateFileW.argtypes = [w.LPCWSTR,w.DWORD,w.DWORD,c.c_void_p,w.DWORD,w.DWORD,w.HANDLE]
    kernel.CreateFileW.restype = w.HANDLE
    handle = kernel.CreateFileW(str(path), 0x80000000, 1, None, 3, 0, None)
    if handle == w.HANDLE(-1).value:
        raise c.WinError(c.get_last_error())
    return os.fdopen(msvcrt.open_osfhandle(handle, os.O_RDONLY | os.O_BINARY), 'rb')


def handoff(installed, cache, version, parent):
    if number(version) <= number(installed) or parent <= 0:
        raise ValueError('Refusing downgrade or invalid parent')
    dest = cache / version
    m = metadata((dest/MANIFEST).read_bytes(), (dest/BUNDLE).read_bytes(), version, authenticate)
    exe = dest / installer_name(version)
    with read_locked(exe) as stream:
        if not matches(stream, m):
            raise ValueError('Staged update changed. Check for updates again.')
        subprocess.Popen([str(exe), '/S', f'/ODUPDATE={parent}'], cwd=dest, close_fds=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--install', nargs=2, metavar=('VERSION','HOST_PID'))
    args = parser.parse_args()
    installed = Path(__file__).with_name('VERSION').read_text().strip()
    cache = Path(os.environ['LOCALAPPDATA']) / 'OpenDirector/Desktop/updates'
    if args.install:
        handoff(installed, cache, args.install[0], int(args.install[1]))
    else:
        # Remove only our obsolete staged packages, not projects/preferences.
        if cache.is_dir():
            for d in cache.iterdir():
                if VERSION.fullmatch(d.name) and number(d.name) <= number(installed) and d.is_dir() and not d.is_junction():
                    for name in (installer_name(d.name), MANIFEST, BUNDLE):
                        try: (d/name).unlink(missing_ok=True)
                        except PermissionError: pass
                    if not any(d.iterdir()): d.rmdir()
        print(stage(installed, cache) or 'NONE')


if __name__ == '__main__':
    try: main()
    except Exception as e:
        # Keep redirect query strings and other HTTP details out of user logs.
        print(f'Update failed ({type(e).__name__}): '+str(e).split('?')[0][:400], file=sys.stderr)
        sys.exit(1)
