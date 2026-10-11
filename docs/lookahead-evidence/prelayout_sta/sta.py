#!/usr/bin/env python3
"""Minimal pre-layout NLDM STA over a Yosys JSON netlist mapped to one Liberty library.

Ideal clock (zero skew, fixed clock slew), no wire load, input delay applied to primary
inputs. Reports the worst arrival time into each register group (by RTL register name).
Intended only for comparing two RTL structures under the same library and flow.
"""
import json, re, sys, collections, bisect

def tokenize(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    text = text.replace('\\\n', ' ')
    return re.findall(r'"(?:[^"\\]|\\.)*"|[A-Za-z0-9_.\-+!\[\]:$]+|[{}();:,]', text)

class Group:
    __slots__ = ('kind', 'args', 'attrs', 'children')
    def __init__(self, kind, args):
        self.kind, self.args, self.attrs, self.children = kind, args, {}, []

def parse_liberty(path):
    toks = tokenize(open(path, encoding='utf-8', errors='replace').read())
    i = 0
    root = Group('root', [])
    stack = [root]
    n = len(toks)
    while i < n:
        t = toks[i]
        if t == '}':
            stack.pop(); i += 1; continue
        if t == ';':
            i += 1; continue
        # name ( args ) { ...    or   name ( args ) ;   or   name : value ;
        if i + 1 < n and toks[i + 1] == ':':
            # simple attribute; value may be several tokens up to ';'
            j = i + 2; vals = []
            while j < n and toks[j] not in (';', '}'):
                vals.append(toks[j]); j += 1
            stack[-1].attrs[t] = ' '.join(vals).strip('"')
            i = j + (1 if j < n and toks[j] == ';' else 0)
            continue
        if i + 1 < n and toks[i + 1] == '(':
            j = i + 2; args = []
            while toks[j] != ')':
                if toks[j] != ',':
                    args.append(toks[j].strip('"'))
                j += 1
            j += 1
            if j < n and toks[j] == '{':
                g = Group(t, args)
                stack[-1].children.append(g)
                stack.append(g)
                i = j + 1
            else:
                stack[-1].attrs.setdefault(t, args)
                if t in stack[-1].attrs and stack[-1].attrs[t] is not args:
                    stack[-1].attrs[t] = args
                i = j + (1 if j < n and toks[j] == ';' else 0)
            continue
        i += 1
    return root

def floats(s):
    return [float(x) for x in re.split(r'[ ,]+', s.strip()) if x]

class Table:
    def __init__(self, g, templates):
        tmpl = templates.get(g.args[0] if g.args else '', None)
        idx1 = g.attrs.get('index_1') or (tmpl.attrs.get('index_1') if tmpl else None)
        idx2 = g.attrs.get('index_2') or (tmpl.attrs.get('index_2') if tmpl else None)
        var1 = tmpl.attrs.get('variable_1', 'input_net_transition') if tmpl else 'input_net_transition'
        vals = g.attrs['values']
        rows = [floats(v) for v in vals]
        self.i1 = floats(idx1[0]) if idx1 else [0.0]
        self.i2 = floats(idx2[0]) if idx2 else None
        self.rows = rows
        self.swap = var1.startswith('total_output')
    def lookup(self, slew, load):
        a, b = (load, slew) if self.swap else (slew, load)
        if self.i2 is None:
            vec = self.rows[0] if len(self.rows) == 1 else [r[0] for r in self.rows]
            return interp1(self.i1, vec, a)
        # rows indexed by i1, columns by i2
        r = [interp1(self.i2, row, b) for row in self.rows]
        return interp1(self.i1, r, a)

def interp1(xs, ys, x):
    if len(xs) == 1:
        return ys[0]
    k = bisect.bisect_left(xs, x)
    k = min(max(k, 1), len(xs) - 1)
    x0, x1 = xs[k - 1], xs[k]
    y0, y1 = ys[k - 1], ys[k]
    return y0 + (y1 - y0) * (x - x0) / (x1 - x0)

def load_cells(lib):
    libg = lib.children[0]
    templates = {c.args[0]: c for c in libg.children if c.kind.endswith('template') and c.args}
    cells = {}
    for c in libg.children:
        if c.kind != 'cell':
            continue
        pins = {}
        for p in c.children:
            if p.kind != 'pin':
                continue
            info = {'dir': p.attrs.get('direction'), 'cap': float(p.attrs.get('capacitance', 0) or 0),
                    'arcs': []}
            for t in p.children:
                if t.kind != 'timing':
                    continue
                ttype = t.attrs.get('timing_type', 'combinational')
                if ttype.startswith(('setup', 'hold', 'recovery', 'removal', 'min_pulse', 'skew', 'non_seq')):
                    continue
                tabs = {}
                for tb in t.children:
                    if tb.kind in ('cell_rise', 'cell_fall', 'rise_transition', 'fall_transition') and 'values' in tb.attrs:
                        tabs[tb.kind] = Table(tb, templates)
                if 'cell_rise' in tabs or 'cell_fall' in tabs:
                    info['arcs'].append((t.attrs.get('related_pin', '').strip('"'), ttype, tabs))
            pins[p.args[0]] = info
        cells[c.args[0]] = {'pins': pins, 'ff': any(ch.kind == 'ff' for ch in c.children)}
    return cells

def arc_delay(tabs, slew, load):
    d = max(tabs[k].lookup(slew, load) for k in ('cell_rise', 'cell_fall') if k in tabs)
    s = max([tabs[k].lookup(slew, load) for k in ('rise_transition', 'fall_transition') if k in tabs] or [slew])
    return d, s

def main():
    netlist, libpath, input_delay, clk_slew, in_slew, out_load, bufcell = sys.argv[1:8]
    FANOUT_MAX = 8
    input_delay, clk_slew, in_slew, out_load = map(float, (input_delay, clk_slew, in_slew, out_load))
    cells = load_cells(parse_liberty(libpath))
    nl = json.load(open(netlist))
    top = [m for m in nl['modules'].values() if m.get('attributes', {}).get('top')]
    mod = top[0] if top else list(nl['modules'].values())[0]
    names = {}
    for name, nn in mod['netnames'].items():
        for k, b in enumerate(nn['bits']):
            if isinstance(b, int):
                if b not in names or (names[b].startswith('$') and not name.startswith('$')):
                    names[b] = f'{name}[{k}]' if len(nn['bits']) > 1 else name
    drivers, loads = {}, collections.defaultdict(list)
    for cname, c in mod['cells'].items():
        lc = cells[c['type']]
        for pin, bits in c['connections'].items():
            for b in bits:
                if not isinstance(b, int):
                    continue
                if lc['pins'][pin]['dir'] == 'output':
                    drivers[b] = (cname, pin)
                else:
                    loads[b].append((cname, pin))
    port_in, port_out = set(), set()
    for pname, p in mod['ports'].items():
        for b in p['bits']:
            if isinstance(b, int):
                (port_in if p['direction'] == 'input' else port_out).add(b)
    buf = cells[bufcell]
    buf_in = [p for p, i in buf['pins'].items() if i['dir'] == 'input'][0]
    buf_out = [p for p, i in buf['pins'].items() if i['dir'] == 'output'][0]
    buf_arc = buf['pins'][buf_out]['arcs'][0][2]
    buf_cap = buf['pins'][buf_in]['cap']
    def raw_load(b):
        cap = sum(cells[mod['cells'][cn]['type']]['pins'][pn]['cap'] for cn, pn in loads[b])
        return cap + (out_load if b in port_out else 0.0), max(1, len(loads[b]) + (b in port_out))
    tree = {}
    def buffer_tree(b):
        # Ideal fanout-limited buffer tree (max fanout FANOUT_MAX, as in the TT flow):
        # driver sees at most FANOUT_MAX buffer inputs; each level adds one buffer delay.
        if b in tree:
            return tree[b]
        cap, fo = raw_load(b)
        if fo <= FANOUT_MAX:
            tree[b] = (cap, 0.0, None)
            return tree[b]
        avg = cap / fo
        levels = 0; n = fo
        while n > FANOUT_MAX:
            n = -(-n // FANOUT_MAX); levels += 1
        extra, s = 0.0, 0.1
        for _ in range(levels):
            d, s = arc_delay(buf_arc, s, FANOUT_MAX * max(avg, buf_cap))
            extra += d
        tree[b] = (min(fo, n) * buf_cap if levels else cap, extra, s)
        return tree[b]
    def net_load(b):
        return buffer_tree(b)[0]
    arrival, slew = {}, {}
    clock_bits = set(mod['ports']['clk']['bits'])
    for b in port_in:
        arrival[b] = 0.0 if b in clock_bits else input_delay
        slew[b] = in_slew
    # sequential start points
    for cname, c in mod['cells'].items():
        lc = cells[c['type']]
        if not lc['ff']:
            continue
        for pin, bits in c['connections'].items():
            info = lc['pins'][pin]
            if info['dir'] != 'output':
                continue
            for b in bits:
                d, s = 0.0, clk_slew
                for rel, ttype, tabs in info['arcs']:
                    if ttype.startswith('rising_edge') or ttype.startswith('falling_edge'):
                        d2, s2 = arc_delay(tabs, clk_slew, net_load(b))
                        d, s = max(d, d2), max(s, s2)
                extra = buffer_tree(b)[1]
                if extra:
                    d += extra; s = buffer_tree(b)[2]
                arrival[b], slew[b] = d, s
    # constants
    memo_stack = []
    pred = {}
    sys.setrecursionlimit(100000)
    def arr(b):
        if not isinstance(b, int):
            return 0.0, in_slew
        if b in arrival:
            return arrival[b], slew[b]
        if b not in drivers:
            arrival[b], slew[b] = 0.0, in_slew
            return 0.0, in_slew
        cname, opin = drivers[b]
        c = mod['cells'][cname]; lc = cells[c['type']]
        best_a, best_s = 0.0, in_slew
        best_from = None
        L = net_load(b)
        for rel, ttype, tabs in lc['pins'][opin]['arcs']:
            if rel not in c['connections']:
                continue
            ib = c['connections'][rel][0]
            a_in, s_in = arr(ib)
            d, s = arc_delay(tabs, s_in, L)
            if a_in + d > best_a:
                best_a = a_in + d; best_from = ib
            best_s = max(best_s, s)
        extra = buffer_tree(b)[1]
        if extra:
            best_a += extra; best_s = buffer_tree(b)[2]
        arrival[b], slew[b] = best_a, best_s
        pred[b] = (best_from, c['type'])
        return best_a, best_s
    groups = collections.defaultdict(float)
    worst = []
    for cname, c in mod['cells'].items():
        lc = cells[c['type']]
        if not lc['ff']:
            continue
        qbits = [b for pin, bits in c['connections'].items() if lc['pins'][pin]['dir'] == 'output' for b in bits]
        reg = names.get(qbits[0], cname) if qbits else cname
        group = re.sub(r'\[\d+\]$', '', reg)
        for pin, bits in c['connections'].items():
            info = lc['pins'][pin]
            if info['dir'] != 'input' or pin.upper().startswith('CLK') or pin.upper() == 'CLK':
                continue
            for b in bits:
                a, _ = arr(b)
                if a > groups[group]:
                    groups[group] = a
                worst.append((a, reg, pin))
    for b in port_out:
        a, _ = arr(b)
        groups['<outputs>'] = max(groups['<outputs>'], a)
    worst.sort(reverse=True)
    def trace(b):
        out = []
        while b is not None and isinstance(b, int):
            out.append((names.get(b, str(b)), round(arrival.get(b, 0), 3), pred.get(b, (None, 'start'))[1]))
            b = pred.get(b, (None, None))[0]
        return out[::-1]
    import os
    focus = os.environ.get('FOCUS')
    if focus:
        for cname, c in mod['cells'].items():
            lc = cells[c['type']]
            if not lc['ff']: continue
            qb = [b for pin, bits in c['connections'].items() if lc['pins'][pin]['dir'] == 'output' for b in bits]
            if qb and names.get(qb[0], '').startswith(focus):
                for pin, bits in c['connections'].items():
                    if lc['pins'][pin]['dir'] == 'input' and pin.upper() != 'CLK':
                        for x in trace(bits[0]): print(x, file=sys.stderr)
                break
    out = {'groups': dict(sorted(groups.items(), key=lambda kv: -kv[1])), 'worst10': worst[:10]}
    print(json.dumps(out, indent=1))

main()
