#!/usr/bin/env python3
# 诊断 luci-app-store 依赖链，递归下钻找到未选入的根因符号
# 在 iStoreOS 源码根目录执行: python3 ../patches/scripts/diagnose-deps.py
import io
import re

cfg = {}
for line in io.open('.config', encoding='utf-8', errors='replace'):
    s = line.strip()
    m = re.match(r'CONFIG_(\S+?)=([ymn])$', s)
    if m:
        cfg[m.group(1)] = m.group(2)
    m = re.match(r'# CONFIG_(\S+) is not set$', s)
    if m:
        cfg.setdefault(m.group(1), 'n')

pkgs = {}
raw = io.open('tmp/.packageinfo', encoding='utf-8', errors='replace').read()
for block in re.split(r'\n\s*\n', raw):
    info = {}
    for l in block.splitlines():
        l = l.strip()
        if l == '@@':
            continue
        if l.startswith('Package:'):
            info['name'] = l[8:].strip()
        elif l.startswith('Depends:'):
            info['dep'] = l[8:].strip()
        elif l.startswith('Menu-Depends:'):
            info['mdep'] = l[13:].strip()
    if 'name' in info:
        pkgs[info['name']] = info

seen = set()


def analyze(name, depth=0):
    ind = '  ' * depth
    if name in seen:
        return
    seen.add(name)
    st = cfg.get('PACKAGE_' + name)
    p = pkgs.get(name)
    tag = st or '不在.config'
    if p is None:
        tag += '  <<< 不在 packageinfo（feed 里根本没有此包）'
    print('%s- %s [%s]' % (ind, name, tag))
    if st == 'y' or p is None:
        return
    for label, key in (('Depends', 'dep'), ('Menu-Depends', 'mdep')):
        for raw_tok in p.get(key, '').split():
            t = raw_tok.lstrip('+')
            neg = t.startswith('!')
            if neg:
                t = t[1:]
            cond = t.startswith('@')
            if cond:
                t = t[1:]
            t = re.sub(r'\(.*?\)', '', t)
            if not t or t == 'linux':
                continue
            if cond:
                v = cfg.get(t)
                ok = (neg and v in (None, 'n')) or (not neg and v not in (None, 'n'))
                flag = '' if ok else '  <<< 门槛不满足（根因）'
                print('%s    %s 条件 %s = %s%s' % (ind, label, t, v or '未设置', flag))
            else:
                v = cfg.get('PACKAGE_' + t)
                flag = '' if v == 'y' else ' -> 继续下钻'
                print('%s    %s %s = [%s]%s' % (ind, label, t, v or 'absent', flag))
                if v != 'y':
                    analyze(t, depth + 1)


for root in ('luci-app-store', 'tar', 'taskd'):
    print('--- 根: %s ---' % root)
    analyze(root)
    print()
