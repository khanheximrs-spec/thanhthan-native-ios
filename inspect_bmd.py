#!/usr/bin/env python3
"""Inspect the plain header of a MU-style BMD. Does not decode the 3D model."""
from pathlib import Path
import struct, sys
if len(sys.argv) != 2:
    sys.exit('Usage: python inspect_bmd.py path/to/model.bmd')
p = Path(sys.argv[1]); b = p.read_bytes()
if len(b) < 42 or b[:3] != b'BMD':
    sys.exit('Not a recognized BMD header')
version = b[3]
name = b[4:36].split(b'\0',1)[0].decode('utf-8',errors='replace')
mesh, bones, animations = struct.unpack_from('<HHH',b,36)
print(f'File: {p.name}\nVersion: {version}\nModel: {name}')
print(f'Header meshes: {mesh}\nHeader bones: {bones}\nHeader animations: {animations}')
print('Note: This does not confirm support for the rest of the binary format.')
