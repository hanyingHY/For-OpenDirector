"""Windows x64 release assembly. No downloads or npm/pip on the end user's PC."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / '.work'
APP = WORK / 'app'
SHA = '4360d9eb66b23598d3f637b2288745291e818862'
PY = 'cpython-3.12.16+20261110-x86_64-pc-windows-msvc-install_only_stripped.tar.gz'
FF = 'ffmpeg-9.0.2-essentials_build'
WV = '1.0.2903.40'


def download(url, name, digest=None):
    path = WORK / name
    if not path.exists():
        temp = path.with_suffix('.part')
        with urllib.request.urlopen(url, timeout=120) as r, temp.open('wb') as f:
            shutil.copyfileobj(r, f)
        temp.replace(path)
    if digest and hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != digest:
        raise ValueError('Digest mismatch: ' + name)
    return path


def unpack(path, dest):
    with tarfile.open(path) as archive:
        archive.extractall(dest, filter='data')


def build():
    WORK.mkdir(exist_ok=True)
    shutil.rmtree(APP, ignore_errors=True)
    APP.mkdir()
    (ROOT / 'delivery').mkdir(exist_ok=True)
    src = WORK / ('OpenDirector-' + SHA)
    unpack(download('https://codeload.github.com/ThinkFlowLab/OpenDirector/tar.gz/' + SHA, 'upstream.tgz'), WORK)
    npm = shutil.which('npm')
    subprocess.run([npm, 'ci', '--ignore-scripts'], cwd=src, check=True)
    subprocess.run([npm, 'run', 'build'], cwd=src, check=True)
    unpack(download('https://github.com/astral-sh/python-build-standalone/releases/download/20261110/' + PY, PY,
                    '355ee61b8207b91574491b1c6dc9b0ebb4408fc56bfafe498f3ef439314b52dc'), APP)
    runtime = APP / 'python'
    python = runtime / 'python.exe'
    pins = [line for line in (src / 'requirements.txt').read_text().splitlines() if line and line[0].islower()]
    (WORK / 'constraints.txt').write_text('\n'.join(pins))
    import tomllib
    deps = tomllib.loads((src / 'pyproject.toml').read_text())['project']['dependencies']
    subprocess.run([python, '-m', 'pip', 'install', '--only-binary=:all:', '--no-compile', '-c', WORK / 'constraints.txt', *deps], check=True)
    site = runtime / 'Lib/site-packages'
    core = site / 'opendirector'
    shutil.copytree(src / 'packages/core/src/opendirector', core)
    launcher = core/'agent/cli_transport.py'
    original = launcher.read_text(encoding='utf8')
    old = "(cli_bin / 'opendirector.cmd').write_text(f'@\"{sys.executable}\" -m opendirector.cli %*\\n')"
    if original.count(old) != 1: raise ValueError('Unexpected upstream Windows CLI launcher')
    launcher.write_text(original.replace(old, "env['OD_AGENT_PYTHON'] = sys.executable\n        (cli_bin / 'opendirector.cmd').write_text('@\"%OD_AGENT_PYTHON%\" -m opendirector.cli %*\\n', encoding='ascii')"),encoding='utf8')
    shutil.copytree(src / 'apps/api/src/opendirector_api', site / 'opendirector_api')
    bundle = core / '_bundled'
    shutil.copytree(src / 'dist', bundle / 'web')
    shutil.copytree(src / 'packages/agent/skills', bundle / 'skills')
    (bundle / 'bin').mkdir()
    # Select the actual PE, not opencode-ai's npm Unix shim. The baseline build
    # also runs on x64 processors without AVX2.
    import json, base64
    lock = json.loads((src / 'package-lock.json').read_text(encoding='utf8'))['packages']
    agent = lock['node_modules/opencode-windows-x64-baseline']
    archive = download(agent['resolved'], 'agent.tgz')
    assert base64.b64encode(hashlib.file_digest(archive.open('rb'), 'sha512').digest()).decode() == agent['integrity'][7:]
    with tarfile.open(archive) as t:
        with t.extractfile('package/bin/opencode.exe') as f, (bundle/'bin/opencode.exe').open('wb') as out:
            shutil.copyfileobj(f, out)
    shutil.copy2(src/'node_modules/opencode-ai/LICENSE', bundle/'bin/LICENSE.opencode')
    with zipfile.ZipFile(download(f'https://github.com/GyanD/codexffmpeg/releases/download/9.0.2/{FF}.zip', 'ffmpeg.zip',
                    '60f467265b1e312373dbcd92200c2618a74850f98d3d078e94296bb3fa2047ba')) as z:
        for name in ('bin/ffmpeg.exe', 'bin/ffprobe.exe', 'LICENSE', 'README.txt'):
            entry = next((x for x in z.namelist() if x.lower().endswith('/'+name.lower())), None)
            if not entry and name=='README.txt': continue
            if not entry: raise RuntimeError('FFmpeg archive missing '+name+': '+str(z.namelist()[:20]))
            target = APP/'media'/Path(name).name
            target.parent.mkdir(exist_ok=True)
            with z.open(entry) as f, target.open('wb') as out: shutil.copyfileobj(f, out)
    # OpenCode's native skill loader uses rg. Without it a clean installation
    # attempts a first-run download when loading a skill.
    rg = 'ripgrep-15.1.0-x86_64-pc-windows-msvc'
    with zipfile.ZipFile(download(f'https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/{rg}.zip', 'ripgrep.zip',
                    '124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a')) as z:
        for name in ('rg.exe', 'LICENSE-MIT', 'UNLICENSE'):
            dest = APP/'media'/('rg.exe' if name=='rg.exe' else 'ripgrep-'+name)
            entry, = [item for item in z.namelist() if Path(item).name==name]
            dest.write_bytes(z.read(entry))
    with zipfile.ZipFile(download('https://github.com/git-for-windows/git/releases/download/v2.56.1.windows.1/MinGit-2.56.1-64-bit.zip', 'mingit.zip',
                    '4a92850b6e917da4fd010669b614b55dccf5b0ec333a534cc4be4700dfefdafd')) as z:
        z.extractall(APP/'git')
    with zipfile.ZipFile(download(f'https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/{WV}/microsoft.web.webview2.{WV}.nupkg','webview2.nupkg')) as z:
        for name in ('lib/net462/Microsoft.Web.WebView2.Core.dll','lib/net462/Microsoft.Web.WebView2.WinForms.dll',
                     'runtimes/win-x64/native/WebView2Loader.dll','LICENSE.txt'):
            target = APP / ('WebView2-LICENSE.txt' if name=='LICENSE.txt' else Path(name).name)
            entry = next((x for x in z.namelist() if x.lower()==name.lower()), None)
            if not entry: raise RuntimeError('Missing '+name+': '+str([x for x in z.namelist() if x.endswith('.dll') or 'license' in x.lower()][:40]))
            target.write_bytes(z.read(entry))
    shutil.copy2(ROOT/'desktop/service.py', APP)
    shutil.copy2(ROOT/'desktop/cli_entry.py', APP)
    for name in ('LICENSE', 'NOTICE', 'package-lock.json'): shutil.copy2(src/name, APP/name)
    csc = Path(os.environ['WINDIR'])/'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
    result = subprocess.run([csc, '/nologo','/target:winexe','/platform:x64','/codepage:65001', '/out:OpenDirector.exe',
                    '/r:System.Security.dll','/r:System.Windows.Forms.dll','/r:System.Drawing.dll', '/r:Microsoft.Web.WebView2.Core.dll',
                    '/r:Microsoft.Web.WebView2.WinForms.dll', ROOT/'desktop/Host.cs'], cwd=APP, capture_output=True, text=True)
    if result.returncode: raise RuntimeError(result.stdout + result.stderr)
    subprocess.run([csc,'/nologo','/target:exe','/platform:x64','/codepage:65001','/out:OpenDirector-CLI.exe','/r:System.Security.dll',ROOT/'desktop/Cli.cs'],cwd=APP,check=True)
    subprocess.run([python,'-I','-c','from opendirector_api.main import create_app; from opendirector.installation import web_root; assert (web_root()/"index.html").is_file()'], check=True)
    subprocess.run([bundle/'bin/opencode.exe','--version'], check=True)
    subprocess.run([APP/'media/rg.exe','--version'], check=True)
    subprocess.run([APP/'media/ffprobe.exe','-version'], check=True)
    assert 'libx264' in subprocess.check_output([APP/'media/ffmpeg.exe','-hide_banner','-encoders'], text=True)

if __name__ == '__main__':
    try: build()
    except Exception as e:
        print('::error::'+str(e), flush=True)
        raise
