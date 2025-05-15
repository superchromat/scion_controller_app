#!/usr/bin/env python3
"""
json_to_c_struct.py

Reads a JSON file and generates:
  • C typedef struct definitions (topologically sorted)
  • A pretty initializer for the JSON data
  • OSC getter/setter functions for leaf fields, handling nested arrays and matrices

Usage:
    python3 json_to_c_struct.py input.json > output.c
"""
import json, sys, re
from collections import OrderedDict, deque

# Helpers

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

# Build type definitions
struct_defs = OrderedDict()

def type_data(x, hint):
    if isinstance(x, dict):
        mat = is_matrix(x)
        if mat:
            R, C, grid = mat
            base, _ = type_data(grid[0][0], hint)
            raw = [[type_data(cell, hint)[1] for cell in row] for row in grid]
            return f"{base}[{R}][{C}]", raw
        if all(re.fullmatch(r"\d+", k) for k in x):  # array
            items = [x[k] for k in sorted(x, key=int)]
            base, _ = type_data(items[0], hint)
            raw = [type_data(it, hint)[1] for it in items]
            return f"{base}[{len(items)}]", raw
        name = pascal(hint)
        struct_defs.setdefault(name, OrderedDict())
        fields = OrderedDict()
        for k, v in x.items():
            fn = sanitize(k)
            ftype, fraw = type_data(v, hint + '_' + k)
            struct_defs[name][fn] = ftype
            fields[fn] = fraw
        return name, ('struct', fields)
    if isinstance(x, list):
        if not x:
            return 'void*', 'NULL'
        ctype, _ = type_data(x[0], hint)
        raw = [type_data(it, hint)[1] for it in x]
        return f"{ctype}[{len(x)}]", raw
    if isinstance(x, str):
        return 'const char*', f'"{x}"'
    if isinstance(x, bool):
        return 'bool', 'true' if x else 'false'
    if isinstance(x, int):
        return 'int', str(x)
    if isinstance(x, float):
        return 'double', str(x)
    if x is None:
        return 'void*', 'NULL'
    raise TypeError(f"Unsupported JSON type: {type(x)}")

# Pretty-print initializer
def fmt(raw, lvl=0):
    indent = '  ' * lvl
    if isinstance(raw, tuple) and raw[0] == 'struct':
        lines = [indent + '{']
        fields = raw[1]
        for i, (fn, fv) in enumerate(fields.items()):
            comma = ',' if i < len(fields)-1 else ''
            sub = fmt(fv, lvl+1).lstrip()
            lines.append(f"{indent}  .{fn} = {sub}{comma}")
        lines.append(indent + '}')
        return '\n'.join(lines)
    if isinstance(raw, list) and raw and isinstance(raw[0], list):  # matrix
        lines = [indent + '{']
        for i, row in enumerate(raw):
            comma = ',' if i < len(raw)-1 else ''
            lines.append(f"{indent}  {{ {', '.join(row)} }}{comma}")
        lines.append(indent + '}')
        return '\n'.join(lines)
    if isinstance(raw, list) and all(isinstance(e, str) for e in raw):  # numeric array
        return '{ ' + ', '.join(raw) + ' }'
    if isinstance(raw, list):
        lines = [indent + '{']
        for i, it in enumerate(raw):
            comma = ',' if i < len(raw)-1 else ''
            sub = fmt(it, lvl+1).lstrip()
            lines.append(f"{indent}  {sub}{comma}")
        lines.append(indent + '}')
        return '\n'.join(lines)
    return indent + raw

# Topological sort
from collections import deque

def topo_sort(defs):
    deps = {n:set() for n in defs}
    for n, fields in defs.items():
        for t in fields.values():
            m = re.match(r"^([A-Za-z_]\w*)", t)
            if m and m.group(1) in defs and m.group(1) != n:
                deps[n].add(m.group(1))
    in_deg = {n:len(d) for n,d in deps.items()}
    q = deque([n for n,d in in_deg.items() if d==0])
    order = []
    while q:
        u = q.popleft(); order.append(u)
        for v in defs:
            if u in deps[v]:
                deps[v].remove(u); in_deg[v]-=1
                if in_deg[v]==0: q.append(v)
    return order

# Generate OSC getters/setters
def gen_accessors(raw, path, dims):
    # Struct
    if isinstance(raw, tuple) and raw[0]=='struct':
        for name, val in raw[1].items(): gen_accessors(val, path+[name], dims)
        return
    # Array of structs
    if isinstance(raw, list) and raw and isinstance(raw[0], tuple):
        idx = path[-1] + '_idx'
        for name,val in raw[0][1].items(): gen_accessors(val, path+[name], dims+[idx])
        return
    # Matrix (2D) with no parent dims
    if isinstance(raw, list) and raw and isinstance(raw[0], list) and not dims:
        func = '_'.join(path)
        print(f"uint32_t get_{func}(char *buf,int len,int row,int col) {{")
        print("  char address[OSC_BUF_SIZE];")
        addr = '/' + '/'.join(path) + '/%d/%d'
        print(f"  snprintf(address,OSC_BUF_SIZE-1,\"{addr}\",row,col);")
        cfg = 'config' + ''.join(f".{seg}" for seg in path) + '[row][col]'
        print(f"  return tosc_writeMessage(buf,len,address,\"f\",{cfg});")
        print("}")
        print(f"void set_{func}(int row,int col,double v) {{ config{''.join(f'.{seg}' for seg in path)}[row][col]=v; }}")
        return
    # Primitive array under struct
    if isinstance(raw, list) and dims:
        base = path[0]; field = path[-1]; idx = dims[0]
        func = '_'.join(path); length = len(raw)
        # Getter
        print(f"uint32_t get_{func}(char *buf,int len,int {idx}) {{")
        print("  char address[OSC_BUF_SIZE];")
        print(f"  snprintf(address,OSC_BUF_SIZE-1,\"/{base}/%d/{field}\",{idx});")
        fmt_str = '"' + 'f'*length + '"'
        print(f"  return tosc_writeMessage(buf,len,address,{fmt_str},")
        for i in range(length):
            comma = ',' if i<length-1 else ''
            print(f"    config.{base}[{idx}].{field}[{i}]{comma}")
        print("  );")
        print("}")
        # Setter
        print(f"void set_{func}(int {idx},double *v) {{ memcpy(config.{base}[{idx}].{field},v,sizeof(double)*{length}); }}")
        return
    # Primitive leaf
    func = '_'.join(path)
    fmtc = 's' if isinstance(raw,str) and raw.startswith('"') else 'f'
    sig = ['char *buf','int len'] + [f"int {d}" for d in dims]
    print(f"uint32_t get_{func}({', '.join(sig)}) {{")
    print("  char address[OSC_BUF_SIZE];")
    parts=[]; di=0
    for seg in path:
        parts.append(seg)
        if di<len(dims): parts.append('%d'); di+=1
    fmt_str='/'+'/'.join(parts)
    if dims:
        args=','.join(dims)
        print(f"  snprintf(address,OSC_BUF_SIZE-1,\"{fmt_str}\",{args});")
    else:
        print(f"  snprintf(address,OSC_BUF_SIZE-1,\"{fmt_str}\");")
    access='config'
    for i,seg in enumerate(path):
        access+=f".{seg}"+ (f"[{dims[i]}]" if i<len(dims) else '')
    print(f"  return tosc_writeMessage(buf,len,address,\"{fmtc}\",{access});")
    print("}")
    # Setter
    if fmtc=='f': print(f"void set_{func}({','.join(dims+['double v'])}) {{ {access}=v; }}")
    else: print(f"void set_{func}({','.join(dims+['const char *s'])}) {{ {access}=s; }}")

# Main
if __name__=='__main__':
    if len(sys.argv)!=2: sys.exit("Usage: json_to_c_struct.py input.json")
    data=json.load(open(sys.argv[1]))
    rt,raw=type_data(data,'Config')
    # includes
    print('#include <stdbool.h>')
    print('#include <stddef.h>')
    print('#include <stdint.h>')
    print('#include <stdio.h>')
    print('#include "tinyosc.h"\n')
    # structs
    for nm in topo_sort(struct_defs):
        print(f"typedef struct {nm} {{")
        for fn,ct in struct_defs[nm].items():
            m2=re.fullmatch(r"(.+)\[(\d+)\]\[(\d+)\]",ct)
            if m2: print(f"  {m2.group(1)} {fn}[{m2.group(2)}][{m2.group(3)}];")
            else:
                m1=re.fullmatch(r"(.+)\[(\d+)\]",ct)
                if m1: print(f"  {m1.group(1)} {fn}[{m1.group(2)}];")
                else: print(f"  {ct} {fn};")
        print(f"}} {nm};\n")
    # initializer
    print(f"{rt} config =")
    print(fmt(raw,0)+";\n")
    # accessors
    print("// Generated OSC getters/setters")
    gen_accessors(raw,[],[])
