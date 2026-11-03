"""从 perf_slide 的原始 IP 反解 KASLR slide。

静态 _text = 0xffffffc010080000，.text 到 _etext = 0xffffffc0118a0000。
正确的 slide 必须让**所有**采样 IP 都落在可执行的 .text 里（采样点必然是正在
执行的指令），并且大量样本应落在 syscall/调度/时钟这些必然经过的核心函数上。
"""
import bisect, sys, collections

TEXT = 0xffffffc010080000
ETEXT = 0xffffffc0118a0000
CORE = ('svc', 'sys_', 'entry', 'irq', 'softirq', 'sched', 'schedule', 'futex',
        'timer', 'hrtimer', 'clock', 'spin_lock', 'spin_unlock', 'mmap', 'vma',
        'page', 'slab', 'kmem', 'copy_', 'memset', 'memcpy', 'pipe', 'pipe_',
        'read', 'write', 'fs/', 'vfs', 'dentry', 'proc', 'task', 'pid', 'cgroup')

def load_syms(path=None):
    import os
    if path is None:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'symbols.txt')
    syms = []
    try:
        fh = open(path, encoding='utf-8', errors='ignore')
    except OSError:
        return [], []          # 没有符号表也能解：只按 .text 覆盖率排序
    with fh:
        lines = fh.readlines()
    for line in lines:
        parts = line.split()
        if len(parts) >= 2:
            try: syms.append((int(parts[0], 16), parts[1]))
            except ValueError: pass
    syms.sort()
    return syms, [a for a, _ in syms]

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else 'devlog/ips_raw.txt'
    ips = [int(l, 16) for l in open(path) if l.startswith('0x')]
    ips = sorted(set(ips))
    if len(ips) < 20:
        print('too few samples:', len(ips)); return 2
    syms, addrs = load_syms()
    lo, hi = min(ips) & ~0x1FFFFF, max(ips) & ~0x1FFFFF
    results = []
    s = 0x1000000000
    while s < 0x3400000000:
        inside = [ip - s for ip in ips if TEXT <= ip - s < ETEXT]
        if len(inside) >= len(ips) * 0.90:
            score = 0
            names = []
            for off in inside:
                i = bisect.bisect_right(addrs, off) - 1
                nm = syms[i][1] if i >= 0 else '?'
                if any(k in nm for k in CORE):
                    score += 1
                if len(names) < 6:
                    names.append(nm[:26])
            results.append((score, len(inside), s, names))
        s += 0x200000
    if not results:
        print('no candidate kept 90% of the samples inside .text'); return 1
    results.sort(key=lambda r: (-r[1], -r[0]))
    # a handful of samples always come from vvar/vectors; the true base is
    # still the one that maximises .text coverage, so no exact-fit is required.
    print('candidates: %d   samples: %d   span=0x%x' % (len(results), len(ips), hi - lo))
    for score, n, s, names in results[:5]:
        print('  base=0x%016x inside=%d/%d core=%d  %s' %
              (TEXT + s, n, len(ips), score, ' | '.join(names)))
    best = results[0][2]
    print('BEST_BASE=0x%016x' % (TEXT + best))
    return 0

if __name__ == '__main__':
    sys.exit(main())
