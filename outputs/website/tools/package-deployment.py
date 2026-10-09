"""Package the standalone website for the audited host Nginx deployment helper."""
from pathlib import Path
import hashlib
import io
import json
import subprocess
import tarfile

website = Path(__file__).resolve().parents[1]
deployment = website / 'deployment'
destination = website / 'dist'
destination.mkdir(exist_ok=True)
files = [website / 'index.html']
for folder in ['styles', 'js', 'assets']:
    files.extend(sorted(path for path in (website / folder).rglob('*') if path.is_file()))
baseline = json.loads((deployment / 'manifest.json').read_text(encoding='utf-8'))
try:
    process = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=website, text=True, capture_output=True)
    revision = process.stdout.strip() if process.returncode == 0 else baseline['sourceHead']
except OSError:
    revision = baseline['sourceHead']
manifest = {
    'siteUrl': baseline['siteUrl'],
    'productRelease': baseline['productRelease'],
    'sourceHead': revision,
    'files': {path.relative_to(website).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
              for path in files},
}
archive_path = destination / 'suixiangji-website-deploy.tar.gz'

def metadata(info):
    info.uid = info.gid = 0
    info.uname = info.gname = 'root'
    info.mode = 0o644
    return info

with tarfile.open(archive_path, 'w:gz') as archive:
    for path in files:
        archive.add(path, arcname='site/' + path.relative_to(website).as_posix(), filter=metadata)
    entries = {
        'manifest.json': json.dumps(manifest, indent=2).encode('utf-8'),
        'deploy-website.sh': (deployment / 'deploy-website.sh').read_text(encoding='utf-8').encode('utf-8'),
    }
    for name, data in entries.items():
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o755 if name.endswith('.sh') else 0o644
        archive.addfile(info, io.BytesIO(data))
print(json.dumps({'archive': str(archive_path), 'files': len(files),
    'sha256': hashlib.sha256(archive_path.read_bytes()).hexdigest()}, ensure_ascii=False))
