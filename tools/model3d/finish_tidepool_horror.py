"""Local marine materials, eye geometry and a four-legged/pincer rig on the generated body."""
import bpy,sys,pathlib,math,json
from mathutils import Vector
ROOT=pathlib.Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/model3d'));import creature_rig as C
out=ROOT/'assets/3d pipeline/enemy/tidepool_horror'
for d in ('source','review'):(out/d).mkdir(exist_ok=True);(out/d/'.gdignore').touch()
master=out/'source/tidepool_horror_master_v002.blend';assert not master.exists()
body=C.load_body(str(out/'raw/tidepool_horror_body_v001.glb'));V=[v.co.copy() for v in body.data.vertices]
H=max(p.z for p in V);W=max(abs(p.x) for p in V);ymin=min(p.y for p in V);ymax=max(p.y for p in V);D=ymax-ymin
def mat(n,c):
    m=bpy.data.materials.new(n);m.use_nodes=True;m.diffuse_color=(*c,1);p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=.70;return m
teal=mat('Horror_Shell',(.11,.34,.36));rust=mat('Horror_Rust',(.69,.25,.07));ivory=mat('Horror_Barnacles',(.66,.57,.38));yellow=mat('Horror_Eyes',(1,.77,.04));black=mat('Horror_Pupils',(.012,.016,.01))
body.data.materials.clear()
for m in [teal,rust,ivory]:body.data.materials.append(m)
for poly in body.data.polygons:
    p=sum((body.data.vertices[i].co for i in poly.vertices),Vector())/len(poly.vertices)
    value=math.sin(p.x/H*23)+math.sin(p.y/H*19)+math.cos(p.z/H*27)
    poly.material_index=1 if value>1.1 else 0
    if abs(p.x)<W*.26 and H*.39<p.z<H*.52:poly.material_index=2
bones=[('Hips',(0,0,.48*H),(0,0,.56*H),None),('Chest',(0,0,.60*H),(0,0,.70*H),'Hips'),('Head',(0,0,.76*H),(0,0,.94*H),'Chest')]
for s,sign in [('Left',1),('Right',-1)]:
    for k,yy in [('Front',ymin+D*.37),('Back',ymin+D*.70)]:
        n=k+s+'Leg';bones.extend([(n,(sign*.25*W,yy,.40*H),(sign*.47*W,yy,.20*H),'Hips'),(n+'Foot',(sign*.47*W,yy,.20*H),(sign*.62*W,yy,.04*H),n)])
    bones.extend([('Arm'+s,(sign*.22*W,0,.63*H),(sign*.52*W,0,.66*H),'Chest'),('Claw'+s,(sign*.52*W,0,.66*H),(sign*.82*W,0,.72*H),'Arm'+s)])
bones.extend([('BoundsTop',(0,0,H),(0,0,H+.01),'Hips'),('BoundsBase',(0,0,0),(0,0,.01),'Hips')])
arm=C.build_armature(bones)
def region(p):
    s='Left' if p.x>0 else 'Right'
    if p.z<H*.40 and abs(p.x)>W*.15:
        k='Front' if p.y<ymin+D*.54 else 'Back';return [k+s+'Leg',k+s+'LegFoot','Hips']
    if abs(p.x)>W*.4 and p.z>H*.4:return ['Arm'+s,'Claw'+s]
    if p.z>H*.70:return ['Head','Chest']
    return ['Hips','Chest']
C.skin(body,arm,region)
front=min(p.y for p in V if p.z>H*.76 and abs(p.x)<W*.3)
for sign in [-1,1]:
    candidates=[p.y for p in V if abs(p.x-sign*W*.13)<W*.08 and abs(p.z-H*.85)<H*.04]
    surface=min(candidates) if candidates else front
    eye_y=surface+H*.008
    for n,y,scale,m in [('Eye',eye_y,(H*.047,H*.022,H*.061),yellow),('Pupil',eye_y-H*.022,(H*.016,H*.009,H*.025),black)]:
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,location=(sign*W*.13,y,H*.85));ob=bpy.context.object;ob.name=n;ob.scale=scale;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);ob.data.materials.append(m)
        g=ob.vertex_groups.new(name='Head');g.add(list(range(len(ob.data.vertices))),1,'REPLACE');mod=ob.modifiers.new('Eye skin','ARMATURE');mod.object=arm;ob.parent=arm
def idle(t):return {'Head':(C.X,1.5*math.sin(t*math.tau)),'Chest':(C.X,1*math.sin(t*math.tau))}
def walk(t):
    p=idle(t)
    for i,n in enumerate(['FrontLeftLeg','BackRightLeg','FrontRightLeg','BackLeftLeg']):p[n]=(C.X,14*math.sin(t*math.tau+(math.pi if i>1 else 0)))
    return p
def strike(t):
    k=math.sin(t*math.pi);return {'ArmLeft':(C.X,-32*k),'ArmRight':(C.X,-32*k),'ClawLeft':(C.Z,20*k),'ClawRight':(C.Z,-20*k),'Head':(C.X,10*k)}
for n,f,fn in [('idle',60,idle),('walk',30,walk),('attack',18,strike),('skill',24,strike),('hurt',12,lambda t:{'Head':(C.X,-14*math.sin(t*math.pi))}),('death',30,lambda t:{'Hips':(C.Y,78*min(t*1.5,1)),'_hips':(0,0,-H*.20*min(t*1.5,1))})]:C.Clip(arm,n,f).bake(fn)
ad=arm.animation_data;ad.action=bpy.data.actions['idle'];ad.action_slot=ad.action.slots[0];bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(master));bpy.ops.export_scene.gltf(filepath=str(out/'tidepool_horror_v002.glb'),export_format='GLB',export_animation_mode='ACTIONS')
(out/'review/rig_v002.json').write_text(json.dumps({'dimensions':[W*2,D,H],'unweighted':sum(not any(g.weight>0 for g in v.groups) for v in body.data.vertices)},indent=2))
