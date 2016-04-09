#!/usr/bin/env python
import os
import re
import sys
import difflib
from collections import defaultdict

from git import Repo

valid_tag = re.compile(r'^v\d+\.\d(\.\d+)?$')


doc_diffs = {}

if not os.path.exists('vim_source'):
    print('Cloning Vim repository', file=sys.stderr)
    repo = Repo.clone_from('https://github.com/vim/vim', 'vim_source', branch='master')
else:
    repo = Repo('vim_source')

remote = repo.remote()
if remote.fetch():
    remote.pull()

helptags = defaultdict(dict)
last = None


def version_tuple(s):
    v = re.sub('[^\d\.]', '', s).split('.')
    return tuple([int(x) for x in v + ([0] * (3 - len(v)))])


def version_format(v):
    if v[-1] == 0:
        v = v[:-1]
    return '.'.join([str(x) for x in v])


for tag in sorted(repo.tags, key=lambda t: t.commit.committed_date):
    if not valid_tag.match(tag.name):
        continue

    if last is None:
        # Collect the first set of helptags
        last = tag.commit
        for line in last.tree['runtime/doc/tags'].data_stream.read().decode('utf8').split('\n'):
            tag_parts = line.strip().split()
            if tag_parts:
                helptags[tag_parts[0]]['+'] = version_tuple(tag.name)
        continue

    d = tag.commit.diff(last, 'runtime/doc/tags')
    if d:
        file_a = d[0].a_blob.data_stream.read().decode('utf8').split('\n')
        file_b = d[0].b_blob.data_stream.read().decode('utf8').split('\n')
        diff = difflib.Differ()
        last = tag.commit
        version = version_tuple(tag.name)
        print('Processing %s' % (version,), file=sys.stderr)
        for d in diff.compare(file_b, file_a):
            if not d.strip() or d.startswith('?'):
                continue
            if d[0] not in ('+', '-', '~'):
                d = 'x' + d
            delta, helptag, tagfile = d.split()[:-1]
            if delta in ('+', '-'):
                # Sanity check.  Removals should be newer than additions.
                # That's just common sense.  Sometimes the diff will pick up
                # tags moving to different files within the same version.
                opposite = '-' if delta == '+' else '+'
                op_version = helptags[helptag].get(opposite)
                if not op_version or (delta == '-' and version > op_version) \
                        or (delta == '+' and version < op_version):
                    helptags[helptag][delta] = version
            elif helptag not in helptags:
                helptags[helptag]['+'] = version


base = os.path.dirname(__file__)
with open(os.path.join(base, '..', 'plugin', 'tags.txt'), 'wt') as fp:
    print('{', file=fp)
    for helptag, status in sorted(helptags.items(), key=lambda x: x[0]):
        helptag = re.sub(r"'", r"''", helptag)
        status = {k: version_format(v) for k, v in status.items()}
        print('\'%s\': %r,' % (helptag, status), file=fp)
    print('}', file=fp)
