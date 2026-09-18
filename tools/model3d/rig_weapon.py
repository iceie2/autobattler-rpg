"""Attach a standalone weapon prop mesh to a character's hand bone (or any
other bone — e.g. a back-holster mount). Blender script.

Meshy generates a held weapon as a COMPLETELY SEPARATE mesh with no rig, no
skin, and no relationship to the character at all — there is no shortcut
around manually placing it.

Two placement modes:

  AIM-DERIVED (default): give --grip-bone and --aim-bone. The gun's own local
  FORWARD axis (its long axis — a per-weapon fact; this rifle's barrel runs
  along local +X, measured from its bounding box) is rotated to point from
  the grip hand toward the second bone, at a specific clip/frame, so the gun
  bridges the two hands the way it's actually held in THAT pose. A single
  rigid bind can't look perfect in every clip the hands strike a different
  relative shape in (measured: Headhunter's aim-pose calibration looked fine
  in `aim` but wrong in `attack`, whose arms are drawn in close instead of
  extended — recalibrating from `attack`'s own hand positions fixed it,
  at idle/aim's expense, which is why this script takes the reference
  clip/frame as an argument instead of hardcoding one).

  MANUAL (pass --aim-bone ""): no direction is derived. --rot-extra IS the
  full rotation (as Euler degrees), and the bone is read at its REST pose
  (no clip needed — leave --aim-clip "") rather than any animated frame. This
  is what a fixed mount point (a back holster) needs: a single, pose-
  independent placement relative to a torso bone.

WHY VERTEX-WEIGHT SKINNING, not parent_type='BONE' (Object > Parent > Bone):
confirmed broken on this rig family — re-importing a bone-parented export
showed the gun's world matrix scrambled to nonsense coordinates (translation
in the TENS, should be under 1). This rig already has one documented
tail_local corruption (add_bulk_shapekey.py); Blender's glTF export path for
an object parented to a bone relies on bone rest length/tail internally, so
it hits the same corruption. Skinning is the exact mechanism the character's
own mesh already uses successfully, so it's proven to survive this rig's
export/import round trip. The skin math (rest-space bake so a POSED
reference frame reproduces correctly) is in `_bind_to_bone` below.

  blender --background --python rig_weapon.py -- \
      --character "...Meshy_AI_Meshy_Merged_Animations (2).glb" \
      --weapon "...Meshy_AI_headhunter_rifle_topo....glb" \
      --grip-bone LeftHand --aim-bone RightHand \
      --aim-clip "Walk_Backward_While_Shooting_inplace" --aim-frame 15 \
      --forward-axis X \
      [--offset 0,0,0] [--rot-extra 0,0,0] [--scale 1.0] [--name Weapon_Held]
      --out "assets/3d pipeline/hero/headhunter/raw/headhunter_with_gun.glb"

  # manual/back-mount example:
  blender --background --python rig_weapon.py -- \
      --character ... --weapon ... \
      --grip-bone Spine01 --aim-bone "" \
      --rot-extra 0,90,15 --offset 0,-0.08,0.02 --name Weapon_Back \
      --out ...
"""
import sys
import bpy
from mathutils import Vector, Euler, Matrix

DEFAULTS = {
    "grip_bone": "LeftHand",
    "aim_bone": "RightHand",
    "aim_clip": "Walk_Backward_with_Bow_Aimed",
    "aim_frame": 1,
    "forward_axis": "X",   # the weapon mesh's own long/barrel axis
    "offset": "0,0,0",     # extra LOCAL (bone-space) translation, after alignment
    "rot_extra": "0,0,0",  # extra LOCAL euler rotation in degrees, applied after
                           # aim alignment (aim-derived mode) or as the FULL
                           # rotation (manual mode, --aim-bone "")
    "offset_world": "0,0,0",  # extra WORLD translation, applied after alignment
    "scale": 1.0,
    "keep_materials": "",  # non-empty: leave the prop's existing material slots
                           # alone instead of flattening to one --color
    "name": "Weapon_Held",  # object name in the output — how runtime code finds it
    # Base colour for the prop, "r,g,b" 0-1. NOT cosmetic polish: a Meshy prop
    # arrives with NO material and NO UVs, and Model3DSprite's toon shader
    # defaults to hint_default_white * white tint, so an unmaterialed prop
    # renders PURE WHITE in game. Cross's white maul against a pale lemur read
    # as no weapon at all (2026-09-09). Default is a dark steel.
    "color": "0.30,0.31,0.34",
    # Explicit WORLD direction for the weapon's forward axis, "x,y,z".
    # Third placement mode, added 2026-09-09. Aim-derived (--aim-bone) can only
    # point a weapon at another JOINT, and on this rig every such direction runs
    # along the forearm -- which fails prop_rubric's A2 (weapon-to-limb
    # clearance) no matter what --rot-extra is added on top, because rotating
    # about the grip cannot move the haft off a line it is already parallel to.
    # A hanging weapon needs a direction that is not a bone: down, and angled
    # away from the arm. Blender world space, Z up, character faces -Y.
    "aim_dir": "",
}


def args():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    o = dict(DEFAULTS)
    o["character"], o["weapon"], o["out"] = None, None, None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a.startswith("--") and i + 1 < len(argv):
            k, v = a[2:].replace("-", "_"), argv[i + 1]
            if k in ("aim_frame",):
                v = int(v)
            elif k == "scale":
                v = float(v)
            o[k] = v
            i += 2
        else:
            i += 1
    return o


def parse_vec3(s):
    parts = [float(x) for x in s.split(",")]
    return Vector(parts)


def main():
    o = args()
    if not (o["character"] and o["weapon"] and o["out"]):
        print(__doc__)
        return

    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    bpy.ops.import_scene.gltf(filepath=o["character"])
    for ob in list(bpy.data.objects):
        if ob.type == "MESH" and "Icosphere" in ob.name:
            bpy.data.objects.remove(ob, do_unlink=True)
    arm = next(ob for ob in bpy.data.objects if ob.type == "ARMATURE")

    # An explicit --aim-dir takes the AIM path (align forward axis onto a
    # direction) rather than the manual path (bone-relative euler); it just
    # supplies the direction itself instead of deriving it from a second bone.
    manual = not o["aim_bone"] and not o.get("aim_dir")
    if manual:
        if o["aim_clip"]:
            print("manual mode: --rot-extra relative to the grip bone's own orientation")
        else:
            print("manual mode: --rot-extra is an absolute world rotation (rest pose)")

    # Posing is independent of manual-vs-aim-derived: pose at a clip whenever
    # one is given (even in manual mode — e.g. binding relative to the hand's
    # OWN orientation mid-attack, not at rest), and only fall back to rest
    # pose when --aim-clip is left empty (the back-holster case).
    if o["aim_clip"]:
        act = bpy.data.actions.get(o["aim_clip"])
        if act is None:
            print("no clip named %r (have: %s)"
                  % (o["aim_clip"], ", ".join(sorted(a.name for a in bpy.data.actions))))
            return
        ad = arm.animation_data or arm.animation_data_create()
        ad.action = act
        if hasattr(ad, "action_slot") and getattr(act, "slots", None):
            ad.action_slot = act.slots[0]
        bpy.context.scene.frame_set(o["aim_frame"])
        bpy.context.view_layer.update()
    else:
        print("no --aim-clip given: rest pose")

    grip_pb = arm.pose.bones[o["grip_bone"]]
    grip_world = arm.matrix_world @ grip_pb.matrix.translation
    print("grip (%s) world: %s" % (o["grip_bone"], grip_world))

    if manual:
        # Relative to the GRIP BONE'S OWN current orientation, not an
        # absolute world euler — a fixed world angle looks wrong whenever the
        # hand itself is oriented unusually (measured: Headhunter's attack
        # clip holds the trigger hand up near the cheek, nothing close to a
        # neutral orientation, so an absolute guess landed the rifle
        # near-vertical through the hood). Riding on the bone's own rotation
        # means --rot-extra only has to correct for how the GUN sits in the
        # hand, which stays comparatively stable across poses even when the
        # hand's own world orientation swings wildly.
        final_quat = None   # computed below straight from rot_extra
    elif not o.get("aim_dir"):
        aim_pb = arm.pose.bones[o["aim_bone"]]
        aim_world = arm.matrix_world @ aim_pb.matrix.translation
        forward = (aim_world - grip_world)
        if forward.length < 1e-6:
            print("grip and aim bones are at the same position — check bone names")
            return
        forward.normalize()
        print("aim  (%s) world: %s" % (o["aim_bone"], aim_world))
        print("forward direction:", forward)

    # Import the weapon into the SAME scene. It has no armature of its own
    # (a raw unrigged prop mesh), so anything with find_armature() is None
    # and wasn't already in the scene before this import is the gun.
    before = {ob.name for ob in bpy.data.objects}
    bpy.ops.import_scene.gltf(filepath=o["weapon"])
    gun = next(ob for ob in bpy.data.objects
               if ob.name not in before and ob.type == "MESH")
    gun.name = o["name"]
    print("weapon mesh:", gun.name)

    import math as _math
    extra_rot = Euler([_math.radians(v) for v in parse_vec3(o["rot_extra"])], 'XYZ').to_quaternion()
    if o.get("aim_dir"):
        forward = Vector(parse_vec3(o["aim_dir"])).normalized()
        print("forward direction (explicit --aim-dir):", forward)
        # Explicit direction wins over both other modes: align the weapon's own
        # forward axis straight onto the world vector the caller asked for.
        local_axis = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)),
                      "Z": Vector((0, 0, 1))}[o["forward_axis"]]
        final_quat = local_axis.rotation_difference(forward) @ extra_rot
    elif manual:
        if o["aim_clip"]:
            # Posed manual mode: relative to the bone's OWN current
            # orientation (see the long comment above this block).
            grip_world_quat = (arm.matrix_world.to_quaternion() @ grip_pb.matrix.to_quaternion()).normalized()
            final_quat = grip_world_quat @ extra_rot
        else:
            # Rest-pose manual mode (a fixed mount point, e.g. the back
            # holster): plain absolute world rotation. There's no unusual
            # bone orientation to accommodate here, and an absolute angle is
            # simpler to reason about for a fixed mount than "relative to
            # whatever this bone's rest orientation happens to be."
            final_quat = extra_rot
    else:
        if o.get("aim_dir"):
            forward = Vector(parse_vec3(o["aim_dir"])).normalized()
            print("forward direction (explicit --aim-dir):", forward)
        local_axis = {"X": Vector((1, 0, 0)), "Y": Vector((0, 1, 0)), "Z": Vector((0, 0, 1))}[o["forward_axis"]]
        align_quat = local_axis.rotation_difference(forward)
        final_quat = align_quat @ extra_rot

    # --offset is expressed in the prop's OWN aligned frame (X runs along the
    # forward axis). --offset-world is a plain world-space nudge, which is what
    # you want for "move it deeper into the palm": the palm direction is a fact
    # about the character in world space, not about the prop's long axis.
    offset_local = parse_vec3(o["offset"])
    world_pos = grip_world + final_quat @ offset_local + parse_vec3(o["offset_world"])
    target_world = final_quat.to_matrix()
    if o["scale"] != 1.0:
        target_world = target_world @ Matrix.Scale(o["scale"], 3)
    target_world = target_world.to_4x4()
    target_world.translation = world_pos

    # NOT parent_type='BONE' — confirmed broken on this rig: re-importing a
    # bone-parented export showed the gun's world matrix scrambled to
    # nonsense coordinates (translation in the TENS, should be under 1). This
    # rig already has one documented tail_local corruption (add_bulk_shapekey
    # .py); Blender's glTF export path for an object parented to a bone
    # relies on bone rest length/tail internally, so it hits the same
    # corruption. VERTEX-WEIGHT SKINNING instead — the exact mechanism the
    # character's own mesh already uses successfully throughout this whole
    # session, so it's proven to survive this rig's export/import round trip.
    #
    # Skinning binds a vertex in REST pose, not whatever pose is currently
    # applied (the aim clip). So `target_world` (measured AT the aim pose) is
    # converted back to what the gun's REST-space geometry must be for
    # standard single-bone skin deformation to reproduce target_world once
    # the armature is posed back to the aim clip:
    #   rest_vertex = arm.matrix_world @ bone.matrix_local @ pose_bone.matrix^-1
    #                 @ arm.matrix_world^-1 @ target_world
    # (bone.matrix_local is the REST bone-to-armature transform; pose_bone
    # .matrix is the SAME bone's CURRENT posed transform — both read at the
    # aim-clip frame already sampled above.)
    grip_bone_data = arm.data.bones[o["grip_bone"]]
    rest_local = grip_bone_data.matrix_local        # reliable (no tail involved)
    pose_local = grip_pb.matrix                      # posed, same frame as grip_world
    bake_matrix = (arm.matrix_world @ rest_local @ pose_local.inverted()
                   @ arm.matrix_world.inverted() @ target_world)

    # Bake straight into the mesh's own vertex data (in the gun OBJECT's
    # local space). The object's own transform is then forced to identity —
    # local space == world space for this object — with matrix_parent_inverse
    # cancelling the armature's 0.01 object scale so that scale isn't applied
    # a second time on top of what's already baked into the geometry.
    gun.data.transform(bake_matrix)
    gun.matrix_basis.identity()

    # Give the prop a material. Flat base colour only -- these meshes have no
    # UVs, so a texture would have nothing to map to.
    # --keep-materials: a prop that arrived with slots already assigned (e.g.
    # prop_edit.py's axis-band split, which carves out the region that has to
    # shade or glow separately) must NOT be flattened to one flat colour here.
    if o.get("keep_materials") and gun.data.materials:
        print("prop materials kept: %s"
              % [mm.name if mm else None for mm in gun.data.materials])
        _skip_material = True
    else:
        _skip_material = False
    rgb = [float(v) for v in o["color"].split(",")]
    m = bpy.data.materials.new(o["name"] + "_mat")
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.55
    m.diffuse_color = (rgb[0], rgb[1], rgb[2], 1.0)
    if not _skip_material:
        gun.data.materials.clear()
        gun.data.materials.append(m)
        print("prop material %s = %s" % (m.name, rgb))
    gun.parent = arm
    gun.matrix_parent_inverse = arm.matrix_world.inverted()

    mod = gun.modifiers.new("Armature", 'ARMATURE')
    mod.object = arm
    vg = gun.vertex_groups.new(name=o["grip_bone"])
    vg.add(range(len(gun.data.vertices)), 1.0, 'REPLACE')

    dest = o["out"]
    bpy.ops.export_scene.gltf(filepath=dest, export_format="GLB")
    print("wrote %s" % dest)


def bind_mesh_to_bone(arm, prop, bone_name, target_world):
    """Bind a textured prop at the current pose, retaining UVs and materials.

    target_world maps the prop's local vertices to their desired world pose.
    The rest-space bake deliberately uses matrices, never corrupt bone tails.
    Returns the maximum evaluated placement error in world units.
    """
    bone = arm.data.bones[bone_name]
    pose = arm.pose.bones[bone_name]
    expected = [target_world @ v.co for v in prop.data.vertices]
    bake = (arm.matrix_world @ bone.matrix_local @ pose.matrix.inverted()
            @ arm.matrix_world.inverted() @ target_world)
    prop.data.transform(bake)
    prop.parent = arm
    prop.matrix_parent_inverse = arm.matrix_world.inverted()
    prop.matrix_basis.identity()
    prop.vertex_groups.clear()
    group = prop.vertex_groups.new(name=bone_name)
    group.add(range(len(prop.data.vertices)), 1.0, 'REPLACE')
    modifier = prop.modifiers.new('Armature', 'ARMATURE')
    modifier.object = arm
    bpy.context.view_layer.update()
    evaluated = prop.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    error = max((evaluated.matrix_world @ v.co - p).length
                for v, p in zip(mesh.vertices, expected))
    evaluated.to_mesh_clear()
    if error > 1e-4:
        raise RuntimeError(f'{prop.name}: bind error {error:g}')
    return error


if __name__ == '__main__':
    main()
