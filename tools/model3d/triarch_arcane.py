"""Local Arcane Core v002: existing body/rig/actions, rigid focus and cast.
Run in Blender --background --python ... -- --in v001.glb --out v002.glb.
Uses the dedicated hand-child bone approach from attach_prop_socket.py.
"""
import bpy, sys, math, json, struct
from mathutils import Vector, Quaternion

argv = sys.argv[sys.argv.index('--') + 1:]
opts = dict(zip(argv[::2], argv[1::2]))
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=opts['--in'])
for obj in list(bpy.data.objects):
    if obj.name == 'Icosphere' or any(c.name == 'glTF_not_exported' for c in obj.users_collection):
        bpy.data.objects.remove(obj, do_unlink=True)
rig = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
for action in bpy.data.actions:
    action.use_fake_user = True
print('TRIARCH RIG', rig.name, list(rig.data.bones.keys()))
hand = next(b for b in rig.data.bones if b.name.endswith('RightHand'))
rig.animation_data.action = None
rig.data.pose_position = 'REST'
grip = rig.matrix_world @ hand.head_local
parts = []
def material(name, color, metal=0.0):
    m = bpy.data.materials.new(name); m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Metallic'].default_value = metal
    bs.inputs['Roughness'].default_value = 0.35
    return m
gold = material('Triarch Focus Gold', (0.52, 0.28, 0.05), 0.7)
gem = material('Triarch Focus Amethyst', (0.32, 0.08, 0.65), 0.25)
# A compact focus in the hand keeps clear of the body and viewport edges.
bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.035, depth=0.5, location=grip + Vector((0, 0, 0.1)))
parts.append(bpy.context.object); parts[-1].data.materials.append(gold)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1, radius=0.115, location=grip + Vector((0, 0, 0.4)))
parts.append(bpy.context.object); parts[-1].data.materials.append(gem)
bpy.ops.mesh.primitive_torus_add(major_radius=0.145, minor_radius=0.012, major_segments=24, minor_segments=6, location=grip + Vector((0, 0, 0.4)))
parts.append(bpy.context.object); parts[-1].data.materials.append(gold)
bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
prop = bpy.context.object; prop.name = 'Focus_Held'
# Skin entirely to one dedicated socket bone; never bone-parent on this rig.
bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode='EDIT')
socket = rig.data.edit_bones.new('triarch_focus_r')
socket.head = hand.head_local; socket.tail = hand.head_local + Vector((0, 0.05, 0))
socket.parent = rig.data.edit_bones[hand.name]
bpy.ops.object.mode_set(mode='OBJECT')
vg = prop.vertex_groups.new(name='triarch_focus_r')
vg.add(list(range(len(prop.data.vertices))), 1.0, 'REPLACE')
mod = prop.modifiers.new('Focus rigid socket', 'ARMATURE'); mod.object = rig
prop.parent = rig; prop.matrix_parent_inverse = rig.matrix_world.inverted()
rig.data.pose_position = 'POSE'
# Author a symmetric lift/hold/recover clip on the existing rig.
cast = bpy.data.actions.new('triarch_cast'); cast.use_fake_user = True
rig.animation_data_create(); rig.animation_data.action = cast
for frame, lift in [(1, 0), (10, 0.35), (20, 0.9), (32, 0.9), (37, 0.2), (46, 0)]:
    for bone in rig.pose.bones:
        bone.rotation_mode = 'QUATERNION'; bone.rotation_quaternion = Quaternion()
        if bone.name.endswith('RightArm'): bone.rotation_quaternion = Quaternion(Vector((1, 0, 0)), -lift)
        if bone.name.endswith('RightForeArm'): bone.rotation_quaternion = Quaternion(Vector((0, 1, 0)), lift * 0.5)
        if bone.name.endswith('LeftArm'): bone.rotation_quaternion = Quaternion(Vector((1, 0, 0)), -lift * 0.6)
        if bone.name.endswith('Spine'): bone.rotation_quaternion = Quaternion(Vector((1, 0, 0)), lift * 0.12)
        bone.keyframe_insert('rotation_quaternion', frame=frame, group=bone.name)
bpy.context.scene.render.fps = 30
bpy.context.scene.frame_start = 1; bpy.context.scene.frame_end = 46
bpy.context.scene.frame_set(1)
bpy.ops.export_scene.gltf(filepath=opts['--out'], export_format='GLB', export_animations=True, export_animation_mode='ACTIONS', use_selection=False)
with open(opts['--out'], 'rb') as f:
    f.read(12); n, _ = struct.unpack('<II', f.read(8)); data = json.loads(f.read(n))
names = [a.get('name') for a in data.get('animations', [])]
assert 'triarch_cast' in names, names
assert any(n.get('name') == 'Focus_Held' for n in data['nodes'])
print('TRIARCH_ARCANE_BUILD: PASS', names)
