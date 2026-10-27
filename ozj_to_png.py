#!/usr/bin/env python3
"""Extract image-like MU/OZJ samples with Pillow; NEVER executes game binaries.
Usage: python ozj_to_png.py path/to/sample.ozj path/to/output.png
Only works on OZJ variants containing directly readable JPEG data.
"""
from pathlib import Path
import sys
from io import BytesIO
try:
    from PIL import Image
except ImportError:
    sys.exit('Please install Pillow: python -m pip install Pillow')

if len(sys.argv) != 3:
    sys.exit('Usage: python ozj_to_png.py input.ozj output.png')
raw = Path(sys.argv[1]).read_bytes()
for offset in (24, 0, 4, 8, 12, 16):
    try:
        with Image.open(BytesIO(raw[offset:])) as img:
            img.convert('RGBA').save(sys.argv[2], 'PNG')
            print(f'Converted {sys.argv[1]} -> {sys.argv[2]} from offset {offset}; size={img.size}')
            break
    except (OSError, ValueError):
        continue
else:
    sys.exit('Unsupported sample; OZJ variants can use custom packing/encryption.')
