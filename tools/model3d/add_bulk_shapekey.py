"""Add a "bulk" morph target (shape key) to a character. Blender script.

WHY A MORPH TARGET AND NOT BONE SCALE. Making a character get WIDER is not
something a skeleton can express. Bone scale is non-uniform and inherits down the
chain, so it both compounds and shears — measured on this rig, three spine bones
at 1.7 gave the chest 1.7^3 and a pancake head, and adding counters at the neck
and shoulders then stretched the arms into flat planks and squashed the gloves
into discs. Uniform scale avoids all that but by definition cannot make him wider
than taller.

A morph target moves the MESH directly. No hierarchy, so nothing compounds and
nothing shears, and it is exactly the tool this deformation is for. glTF supports
morph targets natively.

HOW THE SHAPE IS BUILT. Each vertex is pushed radially outward from the axis of
whichever bone owns it most, by a fraction of its existing radius. Inflating
along vertex NORMALS instead would also push the top of the head up and the soles
down, making him bigger rather than wider; radial-from-bone thickens each limb
about itself and leaves length alone.

Displacement is scaled by the vertex's weight on that bone, so the effect fades
out naturally at joints instead of creasing.

  blender --background --python add_bulk_shapekey.py -- \
      --model "assets/3d pipeline/hero/bouncer/bouncer.glb" \
      [--name bulk] [--amount 0.55] [--bones Spine,Spine01,Spine02,...]
      [--out other.glb] [--force]

The key is added at value 0, so the model is UNCHANGED until something animates
it. See make_ult_animation.py for the clip that drives it.
"""
import sys
import bpy
from mathutils import Vector

# Torso segments get the FULL --amount; everything else (currently just the
# arms) gets --amount * --arm-factor, so the torso can bulge harder than the
# limbs without a second flag per bone.
TORSO_BONES = {"Hips", "Spine", "Spine01", "Spine02"}

DEFAULTS = {
    "name": "bulk",
    # CALIBRATED 2026-09-05: amount=2.0 is the measured ceiling before the
    # geometry starts to fold into a flat slab that swallows the neck (amt>=2.5
    # visibly degrades, amt>=3.0 is broken). See 3D_PIPELINE.md for the sweep.
    "amount": 2.0,
    "arm_factor": 0.35,
    # Torso and arms. Hands are excluded so the gloves keep their shape, and the
    # head is excluded so he does not turn into a balloon.
    "bones": "Hips,Spine,Spine01,Spine02,LeftArm,RightArm,LeftForeArm,RightForeArm",
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["model"], o["out"], o["force"] = None, None, False
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--force":
            o["force"] = True; i += 1; continue
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:], argv[i + 1]
            if k in ("amount", "arm_factor"):
                v = float(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def main():
    o = args()
    if not o["model"]:
        print(__doc__)
        return
    targets = [b for b in o["bones"].split(",") if b]

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["model"])
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")
    me = next(ob for ob in bpy.data.objects if ob.type == "MESH")

    keys = me.data.shape_keys
    if keys and o["name"] in keys.key_blocks and not o["force"]:
        print("shape key %r already exists. Use --force to rebuild." % o["name"])
        return
    if keys and o["name"] in keys.key_blocks:
        me.shape_key_remove(keys.key_blocks[o["name"]])

    if me.data.shape_keys is None:
        me.shape_key_add(name="Basis", from_mix=False)
    key = me.shape_key_add(name=o["name"], from_mix=False)

    # Bone rest axes in the mesh's own space.
    #
    # NEVER use bone.tail_local. MEASURED on this rig: it is corrupted for
    # EVERY bone (e.g. LeftArm.tail_local.x = 2638 against a mesh that spans
    # only -94..94 total) — a Blender glTF-import quirk, not specific to
    # multi-child bones. Using it as an axis direction is what caused the
    # catastrophic ballooning/folding seen at high push amounts.
    #
    # head_local IS reliable (verified against pose-bone world positions).
    # So direction is derived from THIS bone's head -> its single child's head.
    # A bone with 0 or >1 children (Hips, Spine02) falls back to world-up,
    # which is the right default for a torso segment anyway.
    to_local = me.matrix_world.inverted()

    def bone_head(bname):
        return to_local @ (arm.matrix_world @ arm.data.bones[bname].head_local)

    axes = {}
    for bname in targets:
        b = arm.data.bones.get(bname)
        if b is None:
            print("  ! no bone named %s" % bname)
            continue
        head = bone_head(bname)
        axis = Vector((0, 0, 1))
        if len(b.children) == 1:
            d = bone_head(b.children[0].name) - head
            if d.length > 1e-6:
                axis = d.normalized()
        axes[bname] = (head, axis)

    gidx = {}
    for bname in axes:
        vg = me.vertex_groups.get(bname)
        if vg:
            gidx[vg.index] = bname

    moved = 0
    total_push = 0.0
    for v in me.data.vertices:
        # BLEND the push across every bulk bone this vertex belongs to, weighted.
        # Using only the DOMINANT bone makes the push direction piecewise
        # constant: neighbouring vertices either side of a weight boundary pick
        # different bones with different axes, the displacement jumps, and the
        # torso comes out with a scalloped, frilly silhouette. Summing the
        # weighted contributions makes the field continuous, so the inflation
        # fades smoothly across every joint.
        push = Vector((0.0, 0.0, 0.0))
        w_sum = 0.0
        for g in v.groups:
            bname = gidx.get(g.group)
            if bname is None or g.weight <= 0.001:
                continue
            head, axis = axes[bname]
            rel = v.co - head
            radial = rel - rel.dot(axis) * axis
            r = radial.length
            if r < 1e-6:
                continue
            amt = o["amount"] * (1.0 if bname in TORSO_BONES else o["arm_factor"])
            push += radial.normalized() * (r * amt * g.weight)
            w_sum += g.weight
        if w_sum <= 0.01 or push.length < 1e-9:
            continue
        key.data[v.index].co = v.co + push
        moved += 1
        total_push += push.length

    key.value = 0.0          # inert until animated
    key.slider_min, key.slider_max = 0.0, 1.0
    print("shape key %r: %d/%d verts pushed, mean %.4f, amount %.2f"
          % (o["name"], moved, len(me.data.vertices),
             total_push / max(moved, 1), o["amount"]))

    dest = o["out"] or o["model"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB",
                              export_morph=True)
    print("wrote %s" % dest)


main()
