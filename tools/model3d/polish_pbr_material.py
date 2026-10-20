"""Create a versioned GLB material candidate without touching geometry or clips.

The original binary buffer is retained byte-for-byte. An optional emission
mask is embedded as one additional image. Source parameters and hashes are
saved beside the model in an import-excluded source directory.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import struct
from pathlib import Path


def srgb_to_linear(value: float) -> float:
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def main(args: argparse.Namespace) -> None:
    if args.output.exists():
        raise FileExistsError(f"Choose a new candidate version: {args.output}")
    raw = args.source.read_bytes()
    magic, version, _ = struct.unpack_from("<4sII", raw)
    if magic != b"glTF" or version != 2:
        raise ValueError("Expected a glTF 2 binary model")
    offset, document, binary = 12, None, None
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        if kind == 0x4E4F534A:
            document = json.loads(raw[offset + 8 : offset + 8 + size])
        elif kind == 0x004E4942:
            binary = raw[offset + 8 : offset + 8 + size]
        offset += 8 + size
    original = copy.deepcopy(document)
    original_binary = binary
    material = next(m for m in document["materials"] if m.get("name") == args.material)
    pbr = material.setdefault("pbrMetallicRoughness", {})
    if args.roughness is not None:
        pbr["roughnessFactor"] = args.roughness
    if args.metallic is not None:
        pbr["metallicFactor"] = args.metallic
    extension = "KHR_materials_emissive_strength"
    material.setdefault("extensions", {})[extension] = {"emissiveStrength": args.emission_strength}
    used = document.setdefault("extensionsUsed", [])
    if extension not in used:
        used.append(extension)
    if args.emission_mask:
        png = args.emission_mask.read_bytes()
        binary += b"\x00" * ((-len(binary)) % 4)
        view = len(document["bufferViews"])
        document["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(png)})
        binary += png
        image = len(document["images"])
        document["images"].append({"bufferView": view, "mimeType": "image/png", "name": "SelectiveVioletEmission"})
        texture = len(document["textures"])
        base_texture = document["textures"][pbr["baseColorTexture"]["index"]]
        new_texture = {"source": image}
        if "sampler" in base_texture:
            new_texture["sampler"] = base_texture["sampler"]
        document["textures"].append(new_texture)
        material["emissiveTexture"] = {"index": texture}
        material["emissiveFactor"] = [srgb_to_linear(c) for c in args.emission_color]
    document["buffers"][0]["byteLength"] = len(binary)
    # Geometry, skeletons, transforms, and animation data must remain identical.
    for field in ["meshes", "nodes", "skins", "animations", "accessors", "scenes"]:
        if original.get(field) != document.get(field):
            raise AssertionError(f"Unexpected change to {field}")
    if binary[: len(original_binary)] != original_binary:
        raise AssertionError("Original binary buffer changed")
    encoded = json.dumps(document, separators=(",", ":")).encode("utf-8")
    encoded += b" " * ((-len(encoded)) % 4)
    binary += b"\x00" * ((-len(binary)) % 4)
    total = 12 + 8 + len(encoded) + 8 + len(binary)
    result = struct.pack("<4sII", b"glTF", 2, total)
    result += struct.pack("<II", len(encoded), 0x4E4F534A) + encoded
    result += struct.pack("<II", len(binary), 0x004E4942) + binary
    args.output.write_bytes(result)
    source_dir = args.output.parent / "source"
    source_dir.mkdir(exist_ok=True)
    ignore = source_dir / ".gdignore"
    if not ignore.exists():
        ignore.write_text("", encoding="utf-8")
    report = {
        "source_glb": str(args.source.resolve()),
        "source_sha256": hashlib.sha256(raw).hexdigest(),
        "candidate_glb": str(args.output.resolve()),
        "candidate_sha256": hashlib.sha256(result).hexdigest(),
        "material": args.material,
        "roughness": args.roughness,
        "metallic": args.metallic,
        "emission_strength": args.emission_strength,
        "emission_color_srgb": args.emission_color if args.emission_mask else None,
        "mask_sha256": hashlib.sha256(args.emission_mask.read_bytes()).hexdigest() if args.emission_mask else None,
        "geometry_skeleton_animation_and_original_buffer_unchanged": True,
    }
    report_path = source_dir / f"{args.output.stem}_material_build.json"
    if report_path.exists():
        raise FileExistsError(report_path)
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--material", default="Material_1")
    parser.add_argument("--roughness", type=float)
    parser.add_argument("--metallic", type=float)
    parser.add_argument("--emission-strength", type=float, required=True)
    parser.add_argument("--emission-mask", type=Path)
    parser.add_argument("--emission-color", type=float, nargs=3, default=[0.6, 0.3, 1.0])
    main(parser.parse_args())
