#!/usr/bin/env python3
"""
json_to_c_struct.py

Reads an arbitrary JSON file and generates C typedef struct definitions
and a nicely indented initializer with the JSON data as default values.

Usage:
    python3 json_to_c_struct.py input.json > output.c
"""

import json
import sys
import re
from collections import OrderedDict

# collect struct definitions in registration order (children first)
structs = []  # list of (struct_name, [(field_name, field_type)])


def sanitize_identifier(name):
    s = re.sub(r'\W+', '_', name)
    if re.match(r'^\d', s):
        s = '_' + s
    return s or '_'


def pascal_case(name):
    parts = re.split(r'[_\W]+', name)
    return ''.join(word.capitalize() for word in parts if word)


def is_matrix_dict(d):
    """Detect dicts whose keys are all 'row_col' and form a full matrix."""
    coords = []
    for k, v in d.items():
        m = re.fullmatch(r'(\d+)_(\d+)', k)
        if not m:
            return None
        coords.append((int(m.group(1)), int(m.group(2)), v))
    if not coords:
        return None
    rows = max(r for r, _, _ in coords) + 1
    cols = max(c for _, c, _ in coords) + 1
    grid = [[None] * cols for _ in range(rows)]
    for r, c, v in coords:
        grid[r][c] = v
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] is None:
                return None
    return rows, cols, grid


def get_type_and_data(data, hint):
    """
    Return (ctype_str, raw_data) where raw_data is:
      - ('struct', struct_name, OrderedDict(field→raw_data))
      - list of raw_data for arrays/matrices
      - C literal string for primitives
    """
    # matrix dict => 2D array
    if isinstance(data, dict):
        mat = is_matrix_dict(data)
        if mat:
            rows, cols, grid = mat
            etype, _ = get_type_and_data(grid[0][0], hint)
            raw = []
            for row in grid:
                raw.append([ get_type_and_data(v, hint)[1] for v in row ])
            return f"{etype}[{rows}][{cols}]", raw

        # numeric-keyed dict => 1D array
        if data and all(re.fullmatch(r'\d+', k) for k in data):
            items = [ data[k] for k in sorted(data, key=lambda x: int(x)) ]
            etype, _ = get_type_and_data(items[0], hint)
            raw = [ get_type_and_data(item, hint)[1] for item in items ]
            return f"{etype}[{len(items)}]", raw

        # struct
        fields = []
        inits = OrderedDict()
        for key, val in data.items():
            fname = sanitize_identifier(key)
            ftype, fd = get_type_and_data(val, hint + '_' + key)
            fields.append((fname, ftype))
            inits[fname] = fd
        struct_name = pascal_case(sanitize_identifier(hint))
        if struct_name not in (n for n, _ in structs):
            structs.append((struct_name, fields))
        return struct_name, ('struct', struct_name, inits)

    # array
    if isinstance(data, list):
        if not data:
            return "void*", "NULL"
        etype, _ = get_type_and_data(data[0], hint)
        raw = [ get_type_and_data(item, hint)[1] for item in data ]
        return f"{etype}[{len(data)}]", raw

    # primitives
    if isinstance(data, str):
        return "const char*", f"\"{data}\""
    if isinstance(data, bool):
        return "bool", "true" if data else "false"
    if isinstance(data, int):
        return "int", str(data)
    if isinstance(data, float):
        return "double", str(data)
    if data is None:
        return "void*", "NULL"
    raise TypeError(f"Unsupported JSON data type: {type(data)}")


def print_struct_initializer(raw, level):
    indent = '  ' * level
    # raw = ('struct', name, OrderedDict)
    _, _, fields = raw
    for i, (name, val) in enumerate(fields.items()):
        comma = ',' if i < len(fields)-1 else ''
        # struct nested
        if isinstance(val, tuple) and val[0] == 'struct':
            print(f"{indent}.{name} =")
            print(f"{indent}{{")
            print_struct_initializer(val, level+1)
            print(f"{indent}}}{comma}")
        # array or matrix
        elif isinstance(val, list):
            print(f"{indent}.{name} =")
            print(f"{indent}{{")
            # detect matrix (list of lists of primitives)
            if val and all(isinstance(r, list) for r in val):
                for j, row in enumerate(val):
                    row_comma = ',' if j < len(val)-1 else ''
                    row_vals = ', '.join(row)
                    print(f"{indent}  {{ {row_vals} }}{row_comma}")
            else:
                for j, item in enumerate(val):
                    row_comma = ',' if j < len(val)-1 else ''
                    # nested struct element
                    if isinstance(item, tuple) and item[0] == 'struct':
                        print(f"{indent}  {{")
                        print_struct_initializer(item, level+2)
                        print(f"{indent}  }}{row_comma}")
                    else:
                        print(f"{indent}  {item}{row_comma}")
            print(f"{indent}}}{comma}")
        # primitive
        else:
            print(f"{indent}.{name} = {val}{comma}")


def main():
    if len(sys.argv) != 2:
        print("Usage: python3 json_to_c_struct.py input.json", file=sys.stderr)
        sys.exit(1)
    with open(sys.argv[1]) as f:
        data = json.load(f)
    root_type, raw = get_type_and_data(data, "Config")

    # includes
    print("#include <stdbool.h>")
    print("#include <stddef.h>\n")
    # typedefs
    for struct_name, fields in structs:
        print(f"typedef struct {struct_name} {{")
        for fname, ftype in fields:
            m2 = re.match(r"^(.+)\[(\d+)\]\[(\d+)\]$", ftype)
            if m2:
                base, d1, d2 = m2.group(1), m2.group(2), m2.group(3)
                print(f"  {base} {fname}[{d1}][{d2}];")
            else:
                m1 = re.match(r"^(.+)\[(\d+)\]$", ftype)
                if m1:
                    base, d = m1.group(1), m1.group(2)
                    print(f"  {base} {fname}[{d}];")
                else:
                    print(f"  {ftype} {fname};")
        print(f"}} {struct_name};\n")

    # initializer
    print(f"{root_type} config =")
    print("{")
    print_struct_initializer(raw, 1)
    print("};")

if __name__ == "__main__":
    main()

