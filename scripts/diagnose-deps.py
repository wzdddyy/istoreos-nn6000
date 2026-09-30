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
            # 条件依赖写法: 条件符号:实际包名，如 PACKAGE_TAR_BZIP2:bzip2
            cond_pkg = None
            if ':' in t and re.match(r'^[A-Z0-9_]+:', t):
                csym, cond_pkg = t.split(':', 1)
                cv = cfg.get(csym)
                print('%s    %s 条件 %s = [%s] -> %s' % (ind, label, csym, cv or 'absent', cond_pkg))
                t = cond_pkg
            neg = t.startswith('!')
            if neg:
                t = t[1:]
            is_at = t.startswith('@')
            if is_at:
                t = t[1:]
            t = re.sub(r'\(.*?\)', '', t)
            if not t or t == 'linux':
                continue
            if is_at:
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

# 直接 dump 生成的 Kconfig 原始段落，看 default/depends 真相
print('==== 4. 生成的 Kconfig 原始段落 ====')
import os

candidates = [
    'tmp/.config-package.in',
    'tmp/.config-packages.in',
]
kcfg = None
for c in candidates:
    if os.path.exists(c):
        kcfg = c
        break
if kcfg is None:
    # 退而求其次：扫描 tmp 下所有 .in
    import glob
    found = glob.glob('tmp/.config*.in')
    print('候选文件:', found)
    kcfg = found[0] if found else None

if kcfg:
    print('读取:', kcfg)
    text = io.open(kcfg, encoding='utf-8', errors='replace').read()
    print('文件大小: %d 字节, 行数: %d' % (len(text), text.count('\n') + 1))
    print('config 条目总数(含缩进): %d' % len(re.findall(r'(?m)^\s*config\s+\S+', text)))
    srcs = re.findall(r'(?m)^\s*source\s+(.+)$', text)
    print('source 行数: %d' % len(srcs))
    for s in srcs[:10]:
        print('   source', s.strip())

    def extract_block(t):
        m = re.search(r'(?m)^(\s*)config\s+' + re.escape(t) + r'\b', text)
        if not m:
            return None
        start = m.start()
        # 截到下一个 config 行
        nxt = re.search(r'(?m)^\s*config\s+\S+', text[m.end():])
        end = m.end() + nxt.start() if nxt else len(text)
        return text[start:end].rstrip()

    targets = [
        'DEFAULT_luci-app-store', 'DEFAULT_luci-app-dockerman',
        'PACKAGE_luci-app-store', 'PACKAGE_tar', 'PACKAGE_libuci-lua',
        'PACKAGE_luci-lib-taskd', 'PACKAGE_taskd', 'PACKAGE_luci',
        'PACKAGE_uhttpd',
    ]
    index = {}
    for t in targets:
        index[t] = extract_block(t)
    for t in targets:
        print('---- config %s ----' % t)
        print(index.get(t) or '(不存在)')
        print()
else:
    print('未找到生成的 Kconfig 文件')

print('==== 5. DEFAULT 符号是如何被引用的 ====')
if kcfg:
    for t in ('PACKAGE_luci-app-store', 'PACKAGE_luci-app-dockerman'):
        b = index.get(t) or ''
        for dl in re.findall(r'(?m)^\s*default .*$', b):
            print('%s -> %s' % (t, dl.strip()))
        for dep in re.findall(r'(?m)^\s*depends on .*$', b):
            print('%s -> %s' % (t, dep.strip()))
