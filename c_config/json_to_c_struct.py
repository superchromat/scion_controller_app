#!/usr/bin/env python3
"""
json_to_c_struct.py

Reads an arbitrary JSON file and generates C typedef struct definitions
and a nicely indented initializer with the JSON data as default values.
Usage:
    python3 json_to_c_struct.py input.json > output.c
"""

import json, sys, re
from collections import OrderedDict, defaultdict, deque

# collect struct definitions (struct_name -> OrderedDict(field_name -> field_type))
struct_defs = OrderedDict()

def sanitize(name):
    return re.sub(r"\W|^(?=\d)", "_", name)

def pascal(name):
    return ''.join(w.capitalize() for w in re.split(r"[_\W]+", name) if w)

def is_matrix(d):
    coords = []
    for k, v in d.items():
        m = re.fullmatch(r"(\d+)_(\d+)", k)
        if not m:
            return None
        coords.append((int(m.group(1)), int(m.group(2)), v))
    if not coords:
        return None
    R = max(r for r, _, _ in coords) + 1
    C = max(c for _, c, _ in coords) + 1
    grid = [[None] * C for _ in range(R)]
    for r, c, v in coords:
        grid[r][c] = v
    if any(cell is None for row in grid for cell in row):
        return None
    return R, C, grid

# Build types and raw data tree
def type_data(x, hint):
    if isinstance(x, dict):
        m = is_matrix(x)
        if m:
            R, C, grid = m
            t, _ = type_data(grid[0][0], hint)
            raw = [[type_data(cell, hint)[1] for cell in row] for row in grid]
            return f"{t}[{R}][{C}]", raw
        if all(re.fullmatch(r"\d+", k) for k in x):
            items = [x[k] for k in sorted(x, key=int)]
            t, _ = type_data(items[0], hint)
            raw = [type_data(item, hint)[1] for item in items]
            return f"{t}[{len(items)}]", raw
        # struct
        fields = OrderedDict()
        for k, v in x.items():
            fn = sanitize(k)
            tp, data = type_data(v, hint + '_' + k)
            fields[fn] = data
            struct_defs.setdefault(pascal(hint), OrderedDict())[fn] = tp
        return pascal(hint), ('struct', fields)
    if isinstance(x, list):
        if not x:
            return 'void*', 'NULL'
        t, _ = type_data(x[0], hint)
        raw = [type_data(item, hint)[1] for item in x]
        return f"{t}[{len(x)}]", raw
    if isinstance(x, str): return 'const char*', f'"{x}"'
    if isinstance(x, bool): return 'bool', 'true' if x else 'false'
    if isinstance(x, int): return 'int', str(x)
    if isinstance(x, float): return 'double', str(x)
    if x is None: return 'void*', 'NULL'
    raise TypeError(f"Unsupported type: {type(x)}")

# Format initializer recursively
def fmt(d, lvl=0):
    indent = '  ' * lvl
    if isinstance(d, tuple) and d[0] == 'struct':
        fs = d[1]
        lines = [indent + '{']
        for i, (name, val) in enumerate(fs.items()):
            comma = ',' if i < len(fs) - 1 else ''
            sub = fmt(val, lvl+1).lstrip()
            lines.append(f"{indent}  .{name} = {sub}{comma}")
        lines.append(indent + '}')
        return '\n'.join(lines)
    if isinstance(d, list) and d and isinstance(d[0], list):
        lines = [indent + '{']
        for i, row in enumerate(d):
            rc = ',' if i < len(d)-1 else ''
            lines.append(f"{indent}  {{ {', '.join(row)} }}{rc}")
        lines.append(indent + '}')
        return '\n'.join(lines)
    # inline numeric arrays
    if isinstance(d, list) and all(isinstance(e, str) and re.fullmatch(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?", e) for e in d):
        return '{ ' + ', '.join(d) + ' }'
    if isinstance(d, list):
        lines = [indent + '{']
        for i, item in enumerate(d):
            comma = ',' if i < len(d)-1 else ''
            sub = fmt(item, lvl+1).lstrip()
            lines.append(f"{indent}  {sub}{comma}")
        lines.append(indent + '}')
        return '\n'.join(lines)
    return indent + d

# Topologically sort struct_defs so dependencies come first

def topo_sort(defs):
    deps = {name: set() for name in defs}
    for name, fields in defs.items():
        for ftype in fields.values():
            base = re.match(r"^([A-Za-z_]\w*)", ftype)
            if base and base.group(1) in defs and base.group(1) != name:
                deps[name].add(base.group(1))
    # Kahn's algorithm
    in_deg = {n: len(d) for n, d in deps.items()}
    q = deque(n for n, deg in in_deg.items() if deg == 0)
    order = []
    while q:
        u = q.popleft()
        order.append(u)
        for v in defs:
            if u in deps[v]:
                deps[v].remove(u)
                in_deg[v] -= 1
                if in_deg[v] == 0:
                    q.append(v)
    return order

# Main
if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} input.json", file=sys.stderr)
        sys.exit(1)
    data = json.load(open(sys.argv[1]))
    root_type, raw = type_data(data, 'Config')

    # print includes
    print('#include <stdbool.h>')
    print('#include <stddef.h>\n')
    # print typedefs in topo order
    for nm in topo_sort(struct_defs):
        print(f"typedef struct {nm} {{")
        for fname, ftype in struct_defs[nm].items():
            m2 = re.fullmatch(r"(.+)\[(\d+)\]\[(\d+)\]", ftype)
            if m2:
                base, d1, d2 = m2.groups()
                print(f"  {base} {fname}[{d1}][{d2}];")
            else:
                m1 = re.fullmatch(r"(.+)\[(\d+)\]", ftype)
                if m1:
                    base, d = m1.groups()
                    print(f"  {base} {fname}[{d}];")
                else:
                    print(f"  {ftype} {fname};")
        print(f"}} {nm};\n")
    # print initializer
    print(f"{root_type} config =")
    print(fmt(raw, 0) + ';')
