"""Local sprite-inspired quadruped with a segmented tail and precision-spit clips."""
import bpy, math, pathlib, json
from mathutils import Vector, Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'assets/3d pipeline/enemy/lizard'
for folder in ('source','raw','review'):
    (OUT/folder).mkdir(parents=True,exist_ok=True); (OUT/folder/'.gdignore').touch()
master=OUT/'source/lizard_master_v003.blend'
assert not master.exists(), 'Preserve numbered masters; increment version before rebuilding.'
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name,rgb):
    m=bpy.data.materials.new(name); m.diffuse_color=(*rgb,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*rgb,1); p.inputs['Roughness'].default_value=0.78
    return m
skin=mat('Lizard_Skin',(0.28,0.58,0.13)); belly=mat('Lizard_Belly',(0.61,0.8,0.29))
mark=mat('Lizard_Marks',(0.10,0.29,0.07)); eye=mat('Lizard_Eye',(1.0,0.68,0.06)); black=mat('Lizard_Pupil',(0.012,0.025,0.015)); claw=mat('Lizard_Claw',(0.71,0.75,0.49))
bones=[('Hips',(0,0.22,0.48),(0,0,0.49),None),('Chest',(0,0,0.49),(0,-0.30,0.57),'Hips'),('Head',(0,-0.30,0.57),(0,-0.66,0.79),'Chest'),('Jaw',(0,-0.50,0.62),(0,-0.85,0.62),'Head')]
tail=[(0,0.42,0.42),(0.02,0.67,0.36),(0.13,0.89,0.27),(0.31,1.04,0.19),(0.52,1.02,0.13),(0.66,0.88,0.10)]
for i in range(5): bones.append((f'Tail{i}',tail[i],tail[i+1],'Hips' if i==0 else f'Tail{i-1}'))
for side,x in [('L',0.22),('R',-0.22)]:
    for kind,y in [('Front',-0.25),('Back',0.27)]:
        hip=(x,y,0.46); knee=(x*1.8,y+0.09,0.27); foot=(x*1.75,y-0.10,0.075)
        bones += [(kind+side,hip,knee,'Chest' if kind=='Front' else 'Hips'),(kind+side+'Foot',knee,foot,kind+side)]
bones += [('BoundsBase',(0,0,0),(0,0,0.01),'Hips'),('BoundsTop',(0,-0.55,1.03),(0,-0.55,1.04),'Hips')]
data=bpy.data.armatures.new('LizardRig'); arm=bpy.data.objects.new('Armature',data); bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm; arm.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
for name,h,t,parent in bones:
    b=data.edit_bones.new(name); b.head=h; b.tail=t
    if parent: b.parent=data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT'); arm.select_set(False)
parts=[]
def bind(ob,name,bone,material):
    ob.name=name; ob.data.materials.append(material)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    group=ob.vertex_groups.new(name=bone); group.add(list(range(len(ob.data.vertices))),1,'REPLACE')
    for p in ob.data.polygons: p.use_smooth=True
    parts.append(ob)
def ball(name,center,scale,bone,material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=center)
    ob=bpy.context.object; ob.scale=scale; bind(ob,name,bone,material)
def tube(name,a,b,r1,r2,bone,material):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=12,radius1=r1,radius2=r2,depth=(b-a).length,location=(a+b)/2)
    ob=bpy.context.object; ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler(); bind(ob,name,bone,material)
ball('Haunch',(0,0.22,0.46),(0.28,0.35,0.23),'Hips',skin)
ball('Body',(0,-0.05,0.51),(0.255,0.37,0.22),'Chest',skin)
ball('Belly',(0,-0.12,0.405),(0.235,0.31,0.12),'Chest',belly)
ball('Neck',(0,-0.35,0.62),(0.205,0.24,0.24),'Head',skin)
ball('Head',(0,-0.57,0.78),(0.245,0.30,0.235),'Head',skin)
ball('Snout',(0,-0.78,0.71),(0.225,0.21,0.13),'Head',skin)
ball('Mouth',(0,-0.785,0.627),(0.219,0.191,0.015),'Head',black)
ball('LowerJaw',(0,-0.74,0.599),(0.209,0.23,0.052),'Jaw',belly)
for sign in (-1,1):
    ball('EyeSocket',(sign*0.211,-0.62,0.83),(0.060,0.105,0.12),'Head',mark)
    ball('GoldEye',(sign*0.249,-0.64,0.837),(0.035,0.077,0.09),'Head',eye)
    ball('SlitPupil',(sign*0.278,-0.65,0.837),(0.013,0.021,0.073),'Head',black)
    ball('Nostril',(sign*0.15,-0.949,0.746),(0.026,0.009,0.018),'Head',black)
for i in range(5):
    tube(f'TailSegment{i}',tail[i],tail[i+1],0.145*(1-i/5)**1.1,0.145*(1-(i+1)/5)**1.1+0.006,f'Tail{i}',skin)
    ball('TailJoint',tail[i],(0.14*(1-i/5),)*3,f'Tail{i}',skin)
for side,x in [('L',0.22),('R',-0.22)]:
    for kind,y in [('Front',-0.25),('Back',0.27)]:
        name=kind+side; hip=(x,y,0.46); knee=(x*1.8,y+0.09,0.27); foot=(x*1.75,y-0.10,0.075)
        tube('UpperLeg',hip,knee,0.105 if kind=='Back' else 0.075,0.066,name,skin)
        ball('Knee',knee,(0.073,)*3,name,skin)
        tube('LowerLeg',knee,foot,0.060,0.035,name+'Foot',skin)
        ball('Foot',foot,(0.072,0.11,0.034),name+'Foot',skin)
        for toe in (-1,0,1):
            end=(foot[0]+toe*0.065,foot[1]-0.16,0.043)
            tube('Toe',foot,end,0.020,0.01,name+'Foot',skin)
            tube('Claw',end,(end[0],end[1]-0.04,0.025),0.012,0.002,name+'Foot',claw)
for i in range(7):
    y=0.37-i*0.12; z=0.675 if y>-0.29 else 0.84
    ball('DorsalScale',(0,y,z),(0.070,0.065,0.022),'Hips' if y>0.15 else ('Chest' if y>-0.29 else 'Head'),mark)
for sign in (-1,1):
    for i in range(5): ball('FlankSpot',(sign*0.241,0.26-i*0.115,0.53),(0.012,0.027,0.037),'Hips' if i<2 else 'Chest',mark)
bpy.ops.object.select_all(action='DESELECT')
for p in parts:p.select_set(True)
bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join(); body=bpy.context.object; body.name='LizardBody'
mod=body.modifiers.new('Lizard skin','ARMATURE');mod.object=arm;body.parent=arm
def action(name,frames,fn):
    a=bpy.data.actions.new(name);a.use_fake_user=True;ad=arm.animation_data_create();ad.action=a
    for f in range(frames+1):
        t=f/frames;spec=fn(t)
        for pb in arm.pose.bones:
            pb.rotation_mode='QUATERNION'; axis=pb.bone.matrix_local.to_3x3().inverted()
            direction=Vector((0,1,0)) if name=='death' and pb.name=='Hips' else Vector((1,0,0))
            pb.rotation_quaternion=Quaternion(axis@direction,math.radians(spec.get(pb.name,0)))
            if pb.name.startswith('Tail'):pb.rotation_quaternion=Quaternion(axis@Vector((0,0,1)),math.radians(spec.get(pb.name,0)))
            pb.location=(0,0,0);pb.scale=(1,1,1)
            if name=='death' and pb.name=='Hips': pb.location=axis@Vector((0,0,-0.18*min(t*1.5,1)))
            pb.keyframe_insert('rotation_quaternion',frame=f);pb.keyframe_insert('location',frame=f);pb.keyframe_insert('scale',frame=f)
    if hasattr(ad,'action_slot') and a.slots:ad.action_slot=a.slots[0]
    return a
def idle(t):return {'Chest':math.sin(t*math.tau)*1.2,'Head':-math.sin(t*math.tau)*1.2,**{f'Tail{i}':math.sin(t*math.tau-i*.45)*3 for i in range(5)}}
def walk(t):
    p=idle(t)
    for side,phase in [('L',0),('R',math.pi)]:
        for k,offset in [('Front',0),('Back',math.pi)]:p[k+side]=math.sin(t*math.tau+phase+offset)*14;p[k+side+'Foot']=-p[k+side]*0.7
    return p
def spit(t):
    k=(1-t)**2
    return {'Head':-8*k,'Jaw':24*k,'Chest':3*k,**{f'Tail{i}':-3*k for i in range(5)}}
action('idle',60,idle);action('walk',30,walk);action('attack',15,spit);action('skill',15,spit)
action('aim',26,lambda t:{'Head':-4*min(t*3,1),'Chest':2*min(t*3,1),'Jaw':18*min(t*3,1)})
action('hurt',12,lambda t:{'Head':12*math.sin(math.pi*t),'Chest':-6*math.sin(math.pi*t)})
action('death',30,lambda t:{'Hips':75*min(t*1.5,1),'Head':20*min(t*1.5,1),'Jaw':15*min(t*1.5,1)})
ad=arm.animation_data;ad.action=bpy.data.actions['idle'];ad.action_slot=ad.action.slots[0];bpy.context.scene.frame_set(0);bpy.context.scene.render.fps=30
bpy.ops.wm.save_as_mainfile(filepath=str(master))
bpy.ops.export_scene.gltf(filepath=str(OUT/'lizard_v003.glb'),export_format='GLB',export_animation_mode='ACTIONS')
(OUT/'review/build_v001.json').write_text(json.dumps({'route':'Blender, no paid generation','reference':'lizard_normal.png','vertices':len(body.data.vertices),'bones':len(arm.data.bones),'clips':[a.name for a in bpy.data.actions]},indent=2))
