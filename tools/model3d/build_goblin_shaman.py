"""Blender-only shared Shaman, derived from the untouched Goblin v010 master."""
import sys, pathlib, math, json
import bpy
from mathutils import Vector, Quaternion
ROOT = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'assets/3d pipeline/enemy/goblin/review'))
import pose_lib as B
OUT = ROOT / 'assets/3d pipeline/enemy/goblin_shaman'
for folder in ('source', 'review', 'raw'):
    (OUT / folder).mkdir(parents=True, exist_ok=True)
    (OUT / folder / '.gdignore').touch()
master = OUT / 'source/goblin_shaman_master_v004.blend'
if master.exists():
    raise RuntimeError('Version exists; preserve it and increment the builder version.')
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'assets/3d pipeline/enemy/goblin/source/goblin_master_v010.blend'))
arm = bpy.data.objects['Armature']
for name in ('Knife_Held', 'Bow_Held', 'Quiver_Back'):
    bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)
for a in list(bpy.data.actions):
    if a.name not in ('idle','walk','run','hurt','death'):
        bpy.data.actions.remove(a)
base = B.sample(arm, bpy.data.actions['idle'], 0)
B.apply(arm, base)
# Hold the staff out beside the body, with forearm bent instead of a knife guard.
hand = B.hw(arm, 'RightHand')
shoulder = B.hw(arm, 'RightArm')
target = shoulder + Vector((-0.34, -0.22, -0.38))
pole = Vector((-1, 0, -0.2))
B.two_bone(arm, 'RightArm','RightForeArm','RightHand',target,pole)
base = B.grab(arm)
grip = B.hw(arm, 'RightHand')
socket = 'weapon_r' if 'weapon_r' in arm.data.bones else 'RightHand'
# Convert geometry authored at the posed grip to rest space. Single socket skinning
# then reproduces the intended placement exactly without bone-parent export bugs.
to_rest = arm.matrix_world @ arm.data.bones[socket].matrix_local @ arm.pose.bones[socket].matrix.inverted() @ arm.matrix_world.inverted()
def material(name, color, glow=False):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=0.85
    if glow:
        bs.inputs['Emission Color'].default_value=(*color,1); bs.inputs['Emission Strength'].default_value=0.5
    return m
wood=material('Shaman_Wood',(0.24,0.12,0.045))
wrap=material('Shaman_Wrap',(0.48,0.29,0.11))
focus=material('Shaman_Focus',(1.0,1.0,1.0),True)
parts=[]
def segment(a,b,r,mat):
    a,b=grip+Vector(a),grip+Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=10,radius1=r,radius2=r*0.82,depth=(b-a).length,location=(a+b)/2)
    ob=bpy.context.object; ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    ob.data.materials.append(mat); parts.append(ob)
segment((0,0,-0.65),(0.015,0,0.57),0.035,wood)
segment((0.015,0,0.53),(-0.13,0,0.80),0.03,wood)
segment((-0.13,0,0.80),(-0.10,0,0.96),0.022,wood)
segment((0.015,0,0.53),(0.12,0,0.77),0.029,wood)
segment((0.12,0,0.77),(0.21,0,0.81),0.021,wood)
segment((0,0,-0.11),(0.003,0,0.12),0.043,wrap)
bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=0.082,location=grip+Vector((0,0,0.72)))
bpy.context.object.data.materials.append(focus); parts.append(bpy.context.object)
bpy.ops.object.select_all(action='DESELECT')
for ob in parts: ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join()
staff=bpy.context.object; staff.name='Staff_Held'
world=staff.matrix_world.copy()
for v in staff.data.vertices: v.co=to_rest @ world @ v.co
staff.matrix_world.identity()
vg=staff.vertex_groups.new(name=socket); vg.add(list(range(len(staff.data.vertices))),1.0,'REPLACE')
mod=staff.modifiers.new('Rigid staff socket','ARMATURE'); mod.object=arm
staff.parent=arm
staff.matrix_parent_inverse=arm.matrix_world.inverted()
def pose(f,total,heal):
    B.apply(arm,base)
    # Rise, hold at contact, recover: planted hips/feet throughout.
    t=f/total
    strength=math.sin(min(t/0.5,1)*math.pi/2) if t<=0.5 else math.cos((t-0.5)*math.pi)
    B.rot_world(arm,'RightArm',Quaternion(Vector((1,0,0)),math.radians(-28 if heal else -15)*strength))
    B.rot_world(arm,'LeftArm',Quaternion(Vector((1,0,0)),math.radians(-45 if heal else -25)*strength))
    B.rot_world(arm,'LeftForeArm',Quaternion(Vector((0,0,1)),math.radians(-15)*strength))
    B.rot_world(arm,'Head',Quaternion(Vector((1,0,0)),math.radians(-7)*strength))
    return B.grab(arm)
idle_action=bpy.data.actions['idle']
idle_poses=[]
for f in range(49):
    p=B.sample(arm,idle_action,f)
    for bone in ('RightArm','RightForeArm','RightHand',socket): p[bone]=base[bone]
    idle_poses.append(p)
B.write_action(arm,'idle',B.fix_quat_continuity(idle_poses))
B.write_action(arm,'attack',B.fix_quat_continuity([pose(f,20,False) for f in range(21)]))
B.write_action(arm,'skill',B.fix_quat_continuity([pose(f,24,True) for f in range(25)]))
# Keep all staff-bearing locomotion in the authored grip pose, preserving legs.
for name in ('walk','run'):
    action=bpy.data.actions[name]
    poses=[]
    for f in range(int(action.frame_range[1])+1):
        p=B.sample(arm,action,f)
        for bone in ('RightArm','RightForeArm','RightHand',socket): p[bone]=base[bone]
        poses.append(p)
    B.write_action(arm,name,B.fix_quat_continuity(poses))
for a in bpy.data.actions: a.use_fake_user=True
B.assign(arm,bpy.data.actions['idle']); bpy.context.scene.frame_set(0)
bpy.context.scene.render.fps=24
for mat in bpy.data.objects['char1'].data.materials:
    if mat and mat.use_nodes:
        for node in mat.node_tree.nodes:
            if node.type == 'TEX_IMAGE' and node.image and max(node.image.size) > 1024:
                node.image.scale(1024,1024)
                node.image.pack()
bpy.ops.wm.save_as_mainfile(filepath=str(master))
bpy.ops.export_scene.gltf(filepath=str(OUT/'goblin_shaman_v004.glb'),export_format='GLB',export_animation_mode='ACTIONS')
(OUT/'review/build_v001.json').write_text(json.dumps({'source':'goblin_master_v010.blend','socket':socket,'clips':[a.name for a in bpy.data.actions],'staff_vertices':len(staff.data.vertices),'mesh_shared_across_six_elements':True},indent=2))
B.render_frames(arm,bpy.data.actions['skill'],[0,6,12,18,24],str(OUT/'review'),'mend',yaws=(0,45,90),res=256)
