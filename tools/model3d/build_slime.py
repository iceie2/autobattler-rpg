"""Sprite-inspired opaque jelly dome; custom squash rig, no generation credits."""
import bpy, math, pathlib
from mathutils import Vector
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/3d pipeline/enemy/slime'
for folder in ('source', 'raw', 'review'):
    (OUT/folder).mkdir(parents=True, exist_ok=True)
    (OUT/folder/'.gdignore').touch()
master = OUT/'source/slime_master_v002.blend'
assert not master.exists(), 'Increment version; preserve source masters.'
bpy.ops.wm.read_factory_settings(use_empty=True)
def material(name, rgb, roughness=.32):
    m = bpy.data.materials.new(name); m.use_nodes=True
    m.diffuse_color=(*rgb,1)
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*rgb,1)
    p.inputs['Roughness'].default_value=roughness
    p.inputs['Coat Weight'].default_value=.38
    return m
skin=material('Slime_Jelly',(.26,.65,.12))
rim=material('Slime_Rim',(.15,.40,.07))
eye=material('Slime_Eyes',(.008,.055,.025))
shine=material('Slime_Sheen',(.85,1,.65))
data=bpy.data.armatures.new('SlimeRig'); arm=bpy.data.objects.new('Armature',data)
bpy.context.collection.objects.link(arm); bpy.context.view_layer.objects.active=arm
arm.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
for name,head,tail,parent in [('Root',(0,0,0),(0,0,.1),None),('Jelly',(0,0,.08),(0,0,.9),'Root'),
        ('BoundsTop',(0,0,.94),(0,0,.95),'Root'),
        ('BoundsLeft',(-.70,0,.05),(-.70,0,.06),'Root'),
        ('BoundsRight',(.70,0,.05),(.70,0,.06),'Root'),
        ('BoundsFront',(0,-.56,.05),(0,-.56,.06),'Root'),
        ('BoundsBack',(0,.56,.05),(0,.56,.06),'Root')]:
    b=data.edit_bones.new(name);b.head=head;b.tail=tail
    if parent:b.parent=data.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT');arm.select_set(False)
parts=[]
def bind(ob,name,mat,bone='Jelly'):
    ob.name=name;ob.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    g=ob.vertex_groups.new(name=bone);g.add(list(range(len(ob.data.vertices))),1,'REPLACE')
    for p in ob.data.polygons:p.use_smooth=True
    parts.append(ob)
def ball(name,pos,scale,mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24,ring_count=12,location=pos)
    ob=bpy.context.object;ob.scale=scale;bind(ob,name,mat)
# Closed radial dome with a scalloped puddle lip, no hidden legs or humanoid rig.
verts=[(0,0,.025)];faces=[];segments=48;rings=20
for j in range(rings):
    theta=(j/(rings-1))*math.pi/2
    for i in range(segments):
        a=i*math.tau/segments
        radius=.63*math.cos(theta)
        radius*=1+(.10*math.cos(a*7)+.035*math.sin(a*11))*(1-j/(rings-1))**8
        verts.append((radius*math.cos(a),radius*.87*math.sin(a),.035+.90*math.sin(theta)))
for i in range(segments):faces.append((0,1+(i+1)%segments,1+i))
for j in range(rings-1):
    for i in range(segments):
        a=1+j*segments+i;b=1+j*segments+(i+1)%segments
        faces.append((a,b,b+segments,a+segments))
mesh=bpy.data.meshes.new('JellyDome');mesh.from_pydata(verts,[],faces);mesh.update()
ob=bpy.data.objects.new('JellyDome',mesh);bpy.context.collection.objects.link(ob)
bpy.context.view_layer.objects.active=ob;ob.select_set(True);bind(ob,'JellyDome',skin)
for x in [-.20,.20]:
    ball('Eye',(x,-.43,.54),(.085,.041,.105),eye)
    ball('EyeGlint',(x-.023,-.469,.58),(.024,.014,.025),shine)
ball('LowSmile',(0,-.50,.34),(.18,.023,.019),rim)
for pos,scale in [((-.27,-.24,.78),(.075,.036,.085)),((.30,-.27,.72),(.033,.023,.038))]:
    ball('JellyHighlight',pos,scale,shine)
for x,y,r in [(-.49,-.24,.07),(.45,.27,.08),(.23,-.45,.045)]:
    ball('PuddleBead',(x,y,.07),(r,r,.065),skin)
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();body=bpy.context.object
body.name='SlimeBody';mod=body.modifiers.new('Jelly squash','ARMATURE');mod.object=arm;body.parent=arm
def action(name,frames,fn):
    a=bpy.data.actions.new(name);a.use_fake_user=True;ad=arm.animation_data_create();ad.action=a
    for f in range(frames+1):
        z,lift,tilt=fn(f/frames)
        for pb in arm.pose.bones:
            pb.rotation_mode='XYZ';pb.rotation_euler=(tilt if pb.name=='Jelly' else 0,0,0)
            pb.scale=(1/math.sqrt(z),1/math.sqrt(z),z) if pb.name=='Jelly' else (1,1,1)
            pb.location=(0,lift,0) if pb.name=='Jelly' else (0,0,0)
            for prop in ('rotation_euler','scale','location'):pb.keyframe_insert(prop,frame=f)
    if a.slots:ad.action_slot=a.slots[0]
action('idle',60,lambda t:(1+.035*math.sin(t*math.tau),0,0))
action('walk',30,lambda t:(1+.14*math.sin(t*math.tau),.06*(1-math.cos(t*math.tau)),.08*math.sin(t*math.tau)))
action('attack',15,lambda t:(1-.20*math.sin(t*math.pi),0,-.20*math.sin(t*math.pi)))
action('skill',24,lambda t:(1-.28*math.sin(t*math.pi),0,-.14*math.sin(t*math.pi)))
action('hurt',12,lambda t:(1-.15*math.sin(t*math.pi),0,.13*math.sin(t*math.pi)))
action('death',30,lambda t:(1-.85*min(t*1.4,1),0,0))
ad=arm.animation_data;ad.action=bpy.data.actions['idle'];ad.action_slot=ad.action.slots[0]
bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(master))
bpy.ops.export_scene.gltf(filepath=str(OUT/'slime_v002.glb'),export_format='GLB',export_animation_mode='ACTIONS')
