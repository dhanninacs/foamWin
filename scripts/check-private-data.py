"""Scan committed source, pending files, and Git identities without printing secrets."""
import argparse, io, json, os, pathlib, re, subprocess, tarfile
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--history', action='store_true', help='scan every reachable commit')
p.add_argument('--repository', type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[1])
a = p.parse_args()
repo = a.repository.resolve()
def git(*args):
    return subprocess.check_output(['git', '-C', str(repo), *args], stderr=subprocess.DEVNULL)
rules = {
    'private key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'OpenAI key': rb'\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{24,}\b',
    'GitHub token': rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})\b',
    'AWS key': rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
    'Slack token': rb'\bxox[baprs]-[A-Za-z0-9-]{20,}\b',
}
for label, value in [('local username', os.environ.get('USERNAME')), ('local hostname', os.environ.get('COMPUTERNAME'))]:
    if value and len(value) >= 4:
        rules[label] = rb'(?i)\b' + re.escape(value.encode()) + rb'\b'
rules = {label: re.compile(pattern) for label, pattern in rules.items()}
findings = []
files = 0
def scan(data, path, scope):
    for label, pattern in rules.items():
        if pattern.search(data): findings.append({'scope': scope, 'path': path, 'kind': label})
commits = git('rev-list', '--all').decode().splitlines() if a.history else [git('rev-parse','HEAD').decode().strip()]
for commit in commits:
    with tarfile.open(fileobj=io.BytesIO(git('archive','--format=tar',commit))) as archive:
        for member in archive:
            if member.isfile():
                scan(archive.extractfile(member).read(), member.name, 'commit ' + commit[:12])
                files += 1
    scan(git('show','-s','--format=%an <%ae>%n%cn <%ce>%n%B',commit), '(commit metadata)', 'commit ' + commit[:12])
pending = git('diff','--name-only','--diff-filter=AM','-z').split(b'\0') + git('ls-files','--others','--exclude-standard','-z').split(b'\0')
for name in set(pending):
    if not name: continue
    path = repo / name.decode()
    if path.is_file(): scan(path.read_bytes(), name.decode(), 'working tree')
config = git('config','--local','--list')
if re.search(rb'https?://[^\s/@]+:[^\s/@]+@', config):
    findings.append({'scope':'local config','path':'(Git configuration)','kind':'URL credentials'})
print(json.dumps({'commits_scanned':len(commits),'committed_files_scanned':files,'findings':findings},indent=2))
raise SystemExit(1 if findings else 0)
