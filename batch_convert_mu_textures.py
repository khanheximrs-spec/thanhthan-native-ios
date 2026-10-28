#!/usr/bin/env python3
"""Convert local MU OZJ/OZT textures from ZIP archives to PNG.

The source is read-only. No EXE/DLL is run and no account/server data is used.
Requires Pillow: python3 -m pip install Pillow
Example:
    python3 batch_convert_mu_textures.py --output textures --limit 50 Data.zip
    python3 batch_convert_mu_textures.py --output textures Data.zip Data1.zip Data2.zip
Images alone do not provide models, animation, gameplay or online login.
"""
import argparse
import csv
from io import BytesIO
from pathlib import Path, PurePosixPath
import zipfile

from PIL import Image

WRAPPERS = {".ozj": (0, 24), ".ozt": (4,)}
MAX_PIXELS = 16_000_000
Image.MAX_IMAGE_PIXELS = MAX_PIXELS


def safe_parts(name):
    canonical = name.replace("\\", "/")
    path = PurePosixPath(canonical)
    if (not canonical or canonical.startswith("/") or
            any(p in (".", "..") for p in canonical.split("/")) or
            not path.parts or ":" in path.parts[0]):
        return None
    return path.parts


def decode(raw, extension):
    for offset in WRAPPERS[extension]:
        try:
            with Image.open(BytesIO(raw[offset:])) as image:
                expected = "JPEG" if extension == ".ozj" else "TGA"
                if image.format != expected:
                    continue
                image.load()
                width, height = image.size
                if width <= 0 or height <= 0 or width * height > MAX_PIXELS:
                    continue
                return image.convert("RGBA"), width, height, offset
        except (OSError, ValueError, Image.DecompressionBombError):
            continue
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--limit", type=int, default=0,
                        help="Maximum textures attempted; 0=all")
    parser.add_argument("--max-bytes", type=int, default=16_000_000,
                        help="Maximum uncompressed texture size")
    args = parser.parse_args()
    if args.limit < 0 or args.max_bytes < 1:
        parser.error("Expected --limit >= 0 and --max-bytes > 0")
    args.output.mkdir(parents=True, exist_ok=True)
    rows = []

    def convert(source, name, data, out):
        row = [source, name, str(out), "", "", "", ""]
        if data is None or len(data) > args.max_bytes:
            row[5:] = ["skipped", "Size/read limit"]
        else:
            result = decode(data, Path(name).suffix.lower())
            if result is None:
                row[5:] = ["unsupported", "Unknown image wrapper"]
            else:
                image, width, height, offset = result
                out.parent.mkdir(parents=True, exist_ok=True)
                image.save(out, "PNG")
                row[3:5] = [width, height]
                row[5:] = ["converted", f"offset={offset}"]
        rows.append(row)

    for source in args.inputs:
        if args.limit and len(rows) >= args.limit:
            break
        if zipfile.is_zipfile(source):
            with zipfile.ZipFile(source) as archive:
                for entry in archive.infolist():
                    if args.limit and len(rows) >= args.limit:
                        break
                    parts = safe_parts(entry.filename)
                    if entry.is_dir() or parts is None:
                        continue
                    ext = Path(parts[-1]).suffix.lower()
                    if ext not in WRAPPERS:
                        continue
                    out = args.output / source.stem / Path(*parts)
                    out = out.with_suffix(ext + ".png")
                    data = None
                    if entry.file_size <= args.max_bytes:
                        try:
                            data = archive.read(entry)
                        except (OSError, RuntimeError, zipfile.BadZipFile):
                            pass
                    convert(source.name, entry.filename, data, out)
        elif source.suffix.lower() in WRAPPERS and safe_parts(source.name):
            ext = source.suffix.lower()
            out = (args.output / source.name).with_suffix(ext + ".png")
            data = source.read_bytes() if source.stat().st_size <= args.max_bytes else None
            convert(source.name, source.name, data, out)

    manifest = args.output / "texture-manifest.csv"
    with manifest.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["archive", "source", "png", "width", "height",
                         "status", "detail"])
        writer.writerows(rows)
    print(f"Converted {sum(row[5] == 'converted' for row in rows)}/"
          f"{len(rows)} textures. Manifest: {manifest}")


if __name__ == "__main__":
    main()
