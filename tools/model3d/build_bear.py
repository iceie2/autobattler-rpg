"""Heavy plated bear from the shipped sprite; four-leg custom rig."""
import bpy, math, pathlib
from mathutils import Vector, Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2];OUT=ROOT/'assets/3d pipeline/enemy/bear'
for d in ('source','raw','review'):
    (OUT/d).mkdir(parents=True,exist_ok=True);(OUT/d/'.gdignore').touch()
master=OUT/'source/bear_master_v001.blend';assert not master.exists()
bpy.ops.wm.read_factory_settings(use_empty=True)
def mat(name,c):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*c,1)
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=.83
    return m
fur=mat('Bear_Fur',(.22,.19,.13));plate=mat('Bear_Plates',(.36,.33,.24));muzzle=mat('Bear_Muzzle',(.49,.43,.28))
black=mat('Bear_Nose',(.018,.014,.009));eye=mat('Bear_Eyes',(1,.62,.16));claw=mat('Bear_Claws',(.7,.65,.46))
bones=[('Hips',(0,.34,.83),(0,.12,.90),None),('Chest',(0,.08,.9),(0,-.37,1.05),'Hips'),('Head',(0,-.40,1.08),(0,-.78,1.10),'Chest'),('Jaw',(0,-.62,.91),(0,-.91,.9),'Head')]
for s,x in [('L',.29),('R',-.29)]:
    for k,y in [('Front',-.34),('Back',.38)]:
        bones.extend([(k+s,(x,y,.83),(x*1.2,y,.40),'Chest' if k=='Front' else 'Hips'),(k+s+'Foot',(x*1.2,y,.4),(x*1.2,y-.08,.09),k+s)])
bones.extend([('BoundsBase',(0,0,0),(0,0,.01),'Hips'),('BoundsTop',(0,-.48,1.45),(0,-.48,1.46),'Hips')])
data=bpy.data.armatures.new('BearRig');arm=bpy.data.objects.new('Armature',data);bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm;arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
for n,h,t,p in bones:
    b=data.edit_bones.new(n);b.head=h;b.tail=t
    if p:b.parent=data.edit_bones[p]
bpy.ops.object.mode_set(mode='OBJECT');arm.select_set(False);parts=[]
def bind(ob,n,b,m,smooth=True):
    ob.name=n;ob.data.materials.append(m);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    g=ob.vertex_groups.new(name=b);g.add(list(range(len(ob.data.vertices))),1,'REPLACE')
    for p in ob.data.polygons:p.use_smooth=smooth
    parts.append(ob)
def ball(n,c,s,b,m):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,location=c);ob=bpy.context.object;ob.scale=s;bind(ob,n,b,m)
def taper(n,a,b,r1,r2,bone,m):
    a,b=Vector(a),Vector(b);bpy.ops.mesh.primitive_cone_add(vertices=10,radius1=r1,radius2=r2,depth=(b-a).length,location=(a+b)/2)
    ob=bpy.context.object;ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();bind(ob,n,bone,m,False)
ball('Rump',(0,.34,.79),(.39,.41,.39),'Hips',fur)
ball('HeavyShoulders',(0,-.12,.98),(.43,.47,.43),'Chest',fur)
ball('Head',(0,-.57,1.08),(.30,.29,.30),'Head',fur)
ball('Muzzle',(0,-.81,.99),(.21,.25,.14),'Head',muzzle)
ball('Nose',(0,-1.02,1.04),(.13,.065,.077),'Head',black)
ball('Mouth',(0,-.86,.885),(.19,.16,.014),'Head',black)
ball('Jaw',(0,-.82,.854),(.20,.19,.057),'Jaw',muzzle)
for sign in [-1,1]:
    ball('Ear',(sign*.23,-.49,1.31),(.092,.07,.11),'Head',fur)
    ball('InnerEar',(sign*.23,-.548,1.32),(.055,.018,.065),'Head',black)
    ball('Eye',(sign*.235,-.754,1.17),(.040,.027,.03),'Head',eye)
    ball('Pupil',(sign*.245,-.775,1.17),(.018,.012,.024),'Head',black)
    taper('Brow',(sign*.13,-.78,1.24),(sign*.30,-.65,1.20),.061,.025,'Head',plate)
for s,x in [('L',.29),('R',-.29)]:
    for k,y in [('Front',-.34),('Back',.38)]:
        n=k+s
        ball('UpperLeg',(x,y,.61),(.19,.23,.34),n,fur)
        ball('Shin',(x*1.2,y-.01,.29),(.125,.15,.23),n+'Foot',fur)
        ball('Paw',(x*1.2,y-.12,.12),(.17,.23,.11),n+'Foot',muzzle)
        for toe in [-1,0,1]:
            taper('Claw',(x*1.2+toe*.085,y-.29,.12),(x*1.2+toe*.085,y-.40,.07),.028,.004,n+'Foot',claw)
# Overlapping angular plates follow the sprite's stony layered coat.
for j in range(6):
    y=.62-j*.185
    for i in range(5):
        a=(i-2)*.52
        z=.92+.39*math.cos(a);x=.37*math.sin(a)
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=(x,y,z))
        ob=bpy.context.object;ob.scale=(.14,.21,.085);ob.rotation_euler[1]=-a
        bind(ob,'OverlappingPlate','Hips' if j<2 else 'Chest',plate,False)
for sign in [-1,1]:
    for j in range(4):
        taper('CheekTuft',(sign*.25,-.47,1.13-j*.1),(sign*.33,-.40,.99-j*.1),.075,.005,'Head',plate)
ball('ShortTail',(0,.73,.86),(.10,.14,.10),'Hips',fur)
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();body=bpy.context.object;body.name='BearBody'
mod=body.modifiers.new('Bear skin','ARMATURE');mod.object=arm;body.parent=arm
def action(n,frames,fn):
    a=bpy.data.actions.new(n);a.use_fake_user=True;ad=arm.animation_data_create();ad.action=a
    for f in range(frames+1):
        t=f/frames;spec=fn(t)
        for pb in arm.pose.bones:
            pb.rotation_mode='QUATERNION';axis=pb.bone.matrix_local.to_3x3().inverted()
            direction=Vector((0,1,0)) if n=='death' and pb.name=='Hips' else Vector((1,0,0))
            if n=='skill' and pb.name=='FrontR':direction=Vector((0,0,1))
            pb.rotation_quaternion=Quaternion(axis@direction,math.radians(spec.get(pb.name,0)))
            pb.location=axis@Vector((0,0,-.20*min(t*1.5,1))) if n=='death' and pb.name=='Hips' else (0,0,0)
            pb.keyframe_insert('rotation_quaternion',frame=f);pb.keyframe_insert('location',frame=f)
    if a.slots:ad.action_slot=a.slots[0]
def idle(t):return {'Chest':math.sin(t*math.tau)*1,'Head':-math.sin(t*math.tau)}
def walk(t):
    p=idle(t)
    for s,phase in [('L',0),('R',math.pi)]:
        for k,o in [('Front',0),('Back',math.pi)]:p[k+s]=math.sin(t*math.tau+phase+o)*18;p[k+s+'Foot']=-p[k+s]*.6
    return p
action('idle',60,idle);action('walk',36,walk)
action('attack',18,lambda t:{'Head':-13*math.sin(t*math.pi),'Jaw':24*math.sin(t*math.pi),'Chest':4*math.sin(t*math.pi)})
action('skill',24,lambda t:{'FrontR':-50*math.sin(t*math.pi),'FrontRFoot':-32*math.sin(t*math.pi),'Chest':-6*math.sin(t*math.pi)})
action('hurt',12,lambda t:{'Chest':-7*math.sin(t*math.pi),'Head':12*math.sin(t*math.pi)})
action('death',30,lambda t:{'Hips':78*min(t*1.5,1),'Head':14*min(t*1.5,1)})
ad=arm.animation_data;ad.action=bpy.data.actions['idle'];ad.action_slot=ad.action.slots[0]
bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(master));bpy.ops.export_scene.gltf(filepath=str(OUT/'bear_v001.glb'),export_format='GLB',export_animation_mode='ACTIONS')
