"""Build a technical emission mask from Lumen's existing violet texture accents.

Reads the embedded base-color image in the GLB without changing the model or
painting its albedo. Writes a versioned grayscale material-data map and provenance.
Usage: python build_lumen_emission_mask.py SOURCE.glb OUTPUT.png
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import struct
from pathlib import Path

import numpy as np
from PIL import Image


def build(source: Path, output: Path) -> None:
    if output.exists():
        raise FileExistsError(f"Preserve the existing candidate; choose another version: {output}")
    raw = source.read_bytes()
    magic, version, _ = struct.unpack_from("<4sII", raw)
    if magic != b"glTF" or version != 2:
        raise ValueError("Expected a glTF 2 binary model")
    offset, document, binary = 12, None, None
    while offset < len(raw):
        length, kind = struct.unpack_from("<II", raw, offset)
        data = raw[offset + 8 : offset + 8 + length]
        if kind == 0x4E4F534A:
            document = json.loads(data)
        elif kind == 0x004E4942:
            binary = data
        offset += length + 8
    material = next(m for m in document["materials"] if m.get("name") == "Material_1")
    texture_index = material["pbrMetallicRoughness"]["baseColorTexture"]["index"]
    image = document["images"][document["textures"][texture_index]["source"]]
    view = document["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    image_bytes = binary[start : start + view["byteLength"]]
    albedo = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    rgb = np.asarray(albedo, dtype=np.float32) / 255.0
    # Select bright violet seams/eye accents, excluding neutral dark armor.
    violet = np.clip((rgb[..., 2] - rgb[..., 1] - 0.04) / 0.16, 0.0, 1.0)
    brightness = np.clip((np.maximum(rgb[..., 0], rgb[..., 2]) - 0.18) / 0.45, 0.0, 1.0)
    mask = violet * brightness
    values = np.rint(mask * 255.0).astype(np.uint8)
    output.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(values).convert("RGB").save(output)
    report = {
        "source_glb": str(source.resolve()),
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "embedded_albedo_sha256": hashlib.sha256(image_bytes).hexdigest(),
        "mask_sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
        "size": list(albedo.size),
        "coverage_over_10_percent": float(np.mean(mask > 0.1)),
        "selection": "clamp((blue-green-0.04)/0.16) * clamp((max(red,blue)-0.18)/0.45)",
    }
    output.with_suffix(".json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    build(arguments.source, arguments.output)
