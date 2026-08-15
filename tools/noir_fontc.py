#!/usr/bin/env python3
"""noir-fontc v1: deterministic build-time grayscale font asset compiler.

The tool intentionally performs no runtime integration.  It converts a bounded
font coverage declaration into atlas.r8, atlas.png, preview.png, and a
versioned manifest that a later Noir Scene/host ABI can admit strictly.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont
from fontTools.ttLib import TTFont

SCHEMA = "noir-font-asset-manifest-v1"
REVISION = 1
ASCII_PRINTABLE = "".join(chr(codepoint) for codepoint in range(32, 127))


def fail(message: str) -> None:
    raise SystemExit(f"noir-fontc: {message}")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def load_spec(path: Path) -> dict[str, Any]:
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read spec {path}: {exc}")
    if raw.get("schema") != "noir-fontc-spec-v1":
        fail("spec.schema must equal noir-fontc-spec-v1")
    for key in ("face_id", "font", "pixel_size", "charset", "atlas"):
        if key not in raw:
            fail(f"spec is missing required field {key!r}")
    if not isinstance(raw["face_id"], str) or not raw["face_id"]:
        fail("face_id must be a non-empty string")
    if not isinstance(raw["pixel_size"], int) or raw["pixel_size"] <= 0:
        fail("pixel_size must be a positive integer")
    atlas = raw["atlas"]
    if not isinstance(atlas, dict):
        fail("atlas must be an object")
    for key in ("width", "height", "padding", "mode"):
        if key not in atlas:
            fail(f"atlas is missing required field {key!r}")
    if atlas["mode"] != "gray":
        fail("v1 only supports atlas.mode=gray")
    if not all(isinstance(atlas[key], int) and atlas[key] > 0 for key in ("width", "height")):
        fail("atlas width and height must be positive integers")
    if not isinstance(atlas["padding"], int) or atlas["padding"] < 0:
        fail("atlas.padding must be a non-negative integer")
    if raw["charset"] not in ("ASCII_PRINTABLE",):
        fail("v1 only supports charset=ASCII_PRINTABLE; use extra_text to extend coverage")
    extras = raw.get("extra_text", [])
    if not isinstance(extras, list) or not all(isinstance(value, str) for value in extras):
        fail("extra_text must be an array of strings")
    return raw


def resolve_font(font_ref: str) -> Path:
    candidate = Path(font_ref)
    if candidate.is_file():
        return candidate.resolve()
    try:
        result = subprocess.run(
            ["fc-match", "-f", "%{file}", font_ref],
            text=True,
            capture_output=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        fail(f"cannot resolve font family {font_ref!r}: {exc}")
    resolved = Path(result.stdout.strip())
    if not resolved.is_file():
        fail(f"fontconfig did not resolve a font file for {font_ref!r}")
    return resolved.resolve()


def coverage_from_spec(spec: dict[str, Any]) -> list[str]:
    characters = set(ASCII_PRINTABLE)
    for text in spec.get("extra_text", []):
        characters.update(text)
    codepoints = sorted(ord(character) for character in characters)
    if any(codepoint > 0x7F for codepoint in codepoints):
        fail("v1 fontc coverage is intentionally ASCII-only; declare a v2 CJK shaping plan first")
    return [chr(codepoint) for codepoint in codepoints]


def glyph_id_map(font_path: Path) -> dict[int, int]:
    tt = TTFont(str(font_path), lazy=True)
    try:
        cmap = tt.getBestCmap() or {}
        order = tt.getGlyphOrder()
        index = {name: value for value, name in enumerate(order)}
        return {codepoint: index[name] for codepoint, name in cmap.items() if name in index}
    finally:
        tt.close()


def pack_glyphs(font: ImageFont.FreeTypeFont, characters: list[str], width: int, height: int, padding: int) -> tuple[Image.Image, list[dict[str, Any]]]:
    atlas = Image.new("L", (width, height), 0)
    x = padding
    y = padding
    shelf_height = 0
    glyphs: list[dict[str, Any]] = []
    for slot, character in enumerate(characters):
        bbox = font.getbbox(character)
        if bbox is None:
            fail(f"font lacks glyph for U+{ord(character):04X}")
        left, top, right, bottom = bbox
        mask = font.getmask(character, mode="L")
        mask_width, mask_height = mask.size
        glyph_width = max(1, mask_width)
        glyph_height = max(1, mask_height)
        needed_width = glyph_width + padding * 2
        needed_height = glyph_height + padding * 2
        if x + needed_width > width:
            x = padding
            y += shelf_height
            shelf_height = 0
        if y + needed_height > height:
            fail(f"atlas capacity exhausted at U+{ord(character):04X}; increase atlas dimensions")
        glyph_image = Image.new("L", (glyph_width, glyph_height), 0)
        if mask_width and mask_height:
            glyph_image = Image.frombytes("L", (mask_width, mask_height), bytes(mask))
        atlas.paste(glyph_image, (x + padding, y + padding))
        glyphs.append({
            "codepoint": ord(character),
            "character": character,
            "glyph_id": slot,
            "x": x + padding,
            "y": y + padding,
            "width": glyph_width,
            "height": glyph_height,
            "advance": round(float(font.getlength(character)), 6),
            "bearing_x": left,
            "bearing_y": -top,
        })
        x += needed_width
        shelf_height = max(shelf_height, needed_height)
    return atlas, glyphs


def make_preview(atlas: Image.Image, spec: dict[str, Any], glyph_count: int) -> Image.Image:
    scale = 2
    canvas = Image.new("RGB", (atlas.width * scale, atlas.height * scale + 72), (14, 17, 23))
    enlarged = atlas.resize((atlas.width * scale, atlas.height * scale), Image.Resampling.NEAREST)
    alpha = enlarged.point(lambda value: value)
    ink = Image.new("RGB", enlarged.size, (244, 247, 251))
    canvas.paste(ink, (0, 72), alpha)
    draw = ImageDraw.Draw(canvas)
    label = f"{spec['face_id']}  {spec['pixel_size']}px  {glyph_count} glyphs  atlas-gray"
    draw.text((12, 18), label, fill=(154, 166, 183))
    return canvas


def compile_asset(spec_path: Path, out_dir: Path) -> dict[str, Any]:
    spec = load_spec(spec_path)
    font_path = resolve_font(spec["font"])
    characters = coverage_from_spec(spec)
    glyph_ids = glyph_id_map(font_path)
    font = ImageFont.truetype(str(font_path), spec["pixel_size"])
    atlas_spec = spec["atlas"]
    atlas, glyphs = pack_glyphs(font, characters, atlas_spec["width"], atlas_spec["height"], atlas_spec["padding"])
    for glyph in glyphs:
        codepoint = glyph["codepoint"]
        if codepoint not in glyph_ids:
            fail(f"font cmap lacks U+{codepoint:04X}")
        glyph["font_glyph_id"] = glyph_ids[codepoint]
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_path = out_dir / "atlas.r8"
    png_path = out_dir / "atlas.png"
    preview_path = out_dir / "preview.png"
    raw_path.write_bytes(atlas.tobytes())
    atlas.save(png_path)
    make_preview(atlas, spec, len(glyphs)).save(preview_path)
    ascent, descent = font.getmetrics()
    manifest: dict[str, Any] = {
        "schema": SCHEMA,
        "revision": REVISION,
        "face_id": spec["face_id"],
        "renderer_kind": "atlas-gray",
        "font_source": str(font_path),
        "font_sha256": sha256_file(font_path),
        "atlas_sha256": sha256_file(raw_path),
        "atlas": {
            "width": atlas.width,
            "height": atlas.height,
            "channels": 1,
            "padding": atlas_spec["padding"],
            "mode": "r8",
        },
        "metrics": {
            "pixel_size": spec["pixel_size"],
            "ascent": ascent,
            "descent": descent,
            "line_height": ascent + descent,
        },
        "glyph_count": len(glyphs),
        "glyphs": glyphs,
    }
    payload = json.dumps(manifest, ensure_ascii=True, sort_keys=True, indent=2) + "\n"
    (out_dir / "manifest.json").write_text(payload, encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description="Compile bounded desktop font assets for Noir")
    parser.add_argument("spec", type=Path, help="noir-fontc-spec-v1 JSON file")
    parser.add_argument("--out", type=Path, required=True, help="output asset directory")
    args = parser.parse_args()
    manifest = compile_asset(args.spec, args.out)
    print(json.dumps({
        "face_id": manifest["face_id"],
        "glyph_count": manifest["glyph_count"],
        "font_sha256": manifest["font_sha256"],
        "atlas_sha256": manifest["atlas_sha256"],
        "out": str(args.out),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
