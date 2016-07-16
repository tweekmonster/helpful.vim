import os
import re
import sys
import subprocess

from datetime import date, datetime
from collections import defaultdict

base = os.path.dirname(__file__)
src = os.path.abspath(os.path.join(base, 'src'))
repos = {
    'neovim': 'https://github.com/neovim/neovim.git',
    'vim': 'https://github.com/vim/vim.git',
}

neovim_repo = os.path.join(src, 'neovim')
vim_repo = os.path.join(src, 'vim')

_tag_re = re.compile(br'\*([^*\s]+)\*', re.M)

if not os.path.isdir(src):
    os.makedirs(os.path.join(src))


def command(cmd, print_stdout=False, print_stderr=True, cwd=None):
    """Run a git command and return the stdout as lines.

    The stdout is returned as bytes in case a diff breaks up unicode bytes.
    """
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                         stderr=subprocess.PIPE, cwd=cwd)
    stdout, stderr = p.communicate()

    if print_stdout and stdout:
        print(stdout.decode('utf8'))

    if print_stderr and stderr:
        print(cmd, stderr.decode('utf8'), file=sys.stderr)

    return list(filter(None, stdout.split(b'\n')))


def get_latest(repo):
    path = os.path.join(src, repo)
    if os.path.exists(path):
        return command(['git', 'fetch', '-q'], True, cwd=path)
    else:
        return command(['git', 'clone', '-q', '--bare', '--single-branch',
                        repos.get(repo), path], True)


def doc_diff(path, a, b):
    """Parse diff lines to get tags

    A counter is used to keep track of the additions and deletions.
    """
    tags = defaultdict(int)
    if not a or not b:
        cmd = ['git', 'show', '-U0', '--oneline', a or b, '--',
               'runtime/doc/*.txt']
    else:
        cmd = ['git', 'diff', '-U0', a, b, '--', 'runtime/doc/*.txt']
    stdout = command(cmd, cwd=path)
    i = 0

    while i < len(stdout):
        line = stdout[i]
        i += 1
        if line[:2] != b'@@':
            continue

        delta = line.split()
        deleted = 1
        added = 1
        if b',' in delta[1]:
            deleted = int(delta[1].split(b',')[-1])
        if b',' in delta[2]:
            added = int(delta[2].split(b',')[-1])

        if deleted > 0:
            for t in _tag_re.findall(b' ' + b'  '.join(map(lambda x: x[1:], stdout[i:i+deleted])) + b' '):
                tags[t] -= 1
            i += deleted

        if added > 0:
            for t in _tag_re.findall(b' ' + b'  '.join(map(lambda x: x[1:], stdout[i:i+added])) + b' '):
                tags[t] += 1
            i += added

    return tags


def repo_tags(path):
    """Get tags that can be diff'd."""
    stdout = command(['git', 'log', '--pretty=oneline'], cwd=path)
    first = stdout[-1].decode('utf8').split()[0]
    last = stdout[0].decode('utf8').split()[0]

    cmd = ['git', 'for-each-ref',
           "--format=%(*committerdate:raw)%(committerdate:raw) %(refname) %(objectname)",
           'refs/tags']

    tags = [('alpha', first, None)]
    stdout = command(cmd, print_stderr=False, cwd=path)
    for line in sorted(stdout, key=lambda x: x.split()[0]):
        parts = line.decode('utf8').split()
        timestamp, tz = parts[:2]
        tag_date = date.fromtimestamp(int(timestamp))
        tag, ref = parts[-2:]
        tag = tag.split('/')[-1]
        tags.append((tag, ref, tag_date))
    tags.append(('dev', last, None))
    tags.append(('dev', 'HEAD', None))

    return tags


def collect(repo):
    """Collects the helptag differences between versions."""
    path = os.path.join(src, repo)

    tags = repo_tags(path)
    versions = defaultdict(lambda: {'added': [], 'removed': []})

    for i in range(len(tags) - 1):
        helptags = doc_diff(path, tags[i][1], tags[i+1][1])
        version = versions[tags[i+1][0]]
        for k, v in helptags.items():
            if v < 0:
                version['removed'].append(k)
            elif v > 0:
                version['added'].append(k)

    return [(info, versions[info[0]]) for info in tags]


def generate():
    """Generate the data file for the plugin.

    All byte strings from here.
    """
    get_latest('neovim')
    get_latest('vim')

    tags = defaultdict(lambda: defaultdict(lambda: defaultdict(bytes)))

    for target in (b'neovim', b'vim'):
        for (version, ref, tag_date), deltas in collect(target.decode('ascii')):
            for change, items in deltas.items():
                for item in items:
                    tags[item][target][change] = version.encode('ascii')

    help_width = 78

    with open(os.path.join(base, '..', 'data', 'tags'), 'wb') as fp:
        with open(os.path.join(base, '..', 'doc',
                               'helpful-version.txt'), 'wb') as hfp:

            hfp.write((b'Generated: ' +
                       str(datetime.utcnow().replace(microsecond=0))
                       .encode('utf8') + b' UTC').rjust(help_width))
            hfp.write(b'\n')
            hfp.write(b'*helpful-version.txt* *helpful-version*\n')
            hfp.write(b'\n\n')
            hfp.write(b'A listing of helptags with the versions they became '
                      b'available or were removed.\n\n')

            for helptag, targets in sorted(tags.items(),
                                           key=lambda x: x[0].lower().decode('utf8')):
                # Not creating new tags since it adds too much noise to help
                # completion.
                # tag = b'*v/' + helptag + b'*'
                # hfp.write(tag.rjust(help_width) + b'\n')
                hfp.write(b'\n|' + helptag + b'|\n\n')

                target_versions = []
                for target, versions in targets.items():
                    hfp.write(b'  ' + target.title().rjust(8) + b': ')
                    if versions['added']:
                        hfp.write(b'+' + versions['added'] + b' ')
                    if versions['removed']:
                        hfp.write(b'-' + versions['removed'] + b' ')
                    hfp.write(b'\n')

                    target_versions.append(target + b':' +
                                           versions['added'] + b',' +
                                           versions['removed'])
                fp.write(b'\x07'.join([helptag] + target_versions))
                fp.write(b'\n')


if __name__ == '__main__':
    generate()
