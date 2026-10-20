"""Build distinct fragments from the existing Titan; preserve the source GLB.
Run Blender -b --python tools/model3d/build_cloven_fragments.py from project root.
The fist has a broad body and fractured shoulder; the heart a narrow shell
with a rigid amber core. All animation and skin data remain in the exports.
"""
import bpy, bmesh, os
from mathutils import Vector

ROOT = 'assets/3d pipeline/enemy'
for role in ('fist', 'heart'):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(f'{ROOT}/cloven_titan/cloven_titan_v001.glb'))
    arm = next(o for o in bpy.data.objects if o.type == 'ARMATURE')
    body = max((o for o in bpy.data.objects if o.type == 'MESH'), key=lambda o: len(o.data.vertices))
    # Collapse an outer shoulder into a jagged broken edge, keeping a complete
    # mobile lower body so both survivors can use existing rigged movement.
    xs = [v.co.x for v in body.data.vertices]
    width = max(xs)-min(xs)
    for v in body.data.vertices:
        side = v.co.x > width * 0.22 if role == 'fist' else v.co.x < -width * 0.22
        if side:
            v.co.x *= 0.72 if role == 'fist' else 0.52
        v.co.x *= 1.12 if role == 'fist' else 0.72
    if role == 'heart':
        # Rigid exposed core follows Spine02 using glTF-supported skinning.
        bone = arm.data.bones.get('Spine02') or arm.data.bones['Spine']
        centre = arm.matrix_world @ (bone.head_local + Vector((0, -width*0.20, width*0.08)))
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,
            radius=width*0.12*abs(arm.matrix_world.to_scale().x), location=centre)
        core = bpy.context.object
        core.name = 'Exposed_Heart'
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        group = core.vertex_groups.new(name=bone.name)
        group.add(list(range(len(core.data.vertices))), 1.0, 'REPLACE')
        mod = core.modifiers.new('HeartSkin', 'ARMATURE'); mod.object = arm
        core.parent = arm
        core.matrix_parent_inverse = arm.matrix_world.inverted()
        mat = bpy.data.materials.new('AmberCore'); mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get('Principled BSDF')
        bsdf.inputs['Base Color'].default_value = (1.0, 0.35, 0.04, 1)
        bsdf.inputs['Emission Color'].default_value = (1.0, 0.30, 0.02, 1)
        bsdf.inputs['Emission Strength'].default_value = 2.0
        core.data.materials.append(mat)
    dest = f'{ROOT}/cloven_{role}'
    os.makedirs(dest+'/source', exist_ok=True)
    open(dest+'/source/.gdignore','w').close()
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(dest+f'/source/cloven_{role}_v001.blend'))
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(dest+f'/cloven_{role}_v001.glb'),
        export_format='GLB', export_animations=True)
