#!/usr/bin/env python3
"""Synthetic tests for local MU texture conversion; no game assets used."""
import csv
from io import BytesIO
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from batch_convert_mu_textures import decode, safe_parts

assert safe_parts("Player/armor.ozj") == ("Player", "armor.ozj")
for unsafe in ("../escape.ozj", "/etc/evil.ozt", "C:/evil.ozj",
               "a/../b.ozj", r"..\escape.ozt"):
    assert safe_parts(unsafe) is None, unsafe

image = Image.new("RGB", (8, 6), (20, 80, 160))
jpeg = BytesIO()
image.save(jpeg, "JPEG")
tga = BytesIO()
image.save(tga, "TGA")
assert decode(b"\0" * 24 + jpeg.getvalue(), ".ozj")[1:3] == (8, 6)
assert decode(b"\0" * 4 + tga.getvalue(), ".ozt")[1:3] == (8, 6)
assert decode(b"junk", ".ozj") is None

with tempfile.TemporaryDirectory() as temp:
    root = Path(temp)
    archive = root / "sample.zip"
    with zipfile.ZipFile(archive, "w") as z:
        z.writestr("Player/head.ozj", b"\0" * 24 + jpeg.getvalue())
        z.writestr("Monster/body.ozt", b"\0" * 4 + tga.getvalue())
        z.writestr("../escape.ozj", jpeg.getvalue())
    dest = root / "converted"
    subprocess.run([sys.executable, str(ROOT / "batch_convert_mu_textures.py"),
                    "--output", str(dest), str(archive)], check=True)
    a = dest / "sample/Player/head.ozj.png"
    b = dest / "sample/Monster/body.ozt.png"
    assert a.exists() and b.exists()
    assert not (root / "escape.ozj.png").exists()
    assert Image.open(a).size == (8, 6)
    assert Image.open(b).size == (8, 6)
    with (dest / "texture-manifest.csv").open(newline="") as f:
        rows = list(csv.DictReader(f))
    assert len(rows) == 2 and all(r["status"] == "converted" for r in rows)
print("Synthetic MU ZIP/OZJ/OZT conversion tests passed.")
