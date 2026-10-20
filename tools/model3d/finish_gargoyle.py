"""Separate back-wing weights and stone talon actions; no paid animation calls."""
import bpy,sys,pathlib,math,json
from mathutils import Vector,Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'assets/3d pipeline/enemy/goblin/review'));import pose_lib as B
out=ROOT/'assets/3d pipeline/enemy/gargoyle'
for d in ('source','review'):(out/d).mkdir(exist_ok=True);(out/d/'.gdignore').touch()
master=out/'source/gargoyle_master_v001.blend';assert not master.exists()
arm=B.load(str(out/'raw/history/gargoyle_v001.glb'));body=max((o for o in bpy.data.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
V=[v.co.copy() for v in body.data.vertices];H=max(v.z for v in V);W=max(abs(v.x) for v in V);lo=min(v.y for v in V);hi=max(v.y for v in V);D=hi-lo;cut=lo+.45*D
base=B.sample(arm,bpy.data.actions['idle'],0)
bpy.context.view_layer.objects.active=arm;bpy.ops.object.mode_set(mode='EDIT');eb=arm.data.edit_bones
for side,sign in [('Left',1),('Right',-1)]:
    b=eb.new('Wing'+side);b.head=(sign*.24*W,lo+.66*D,.66*H);b.tail=(sign*.90*W,lo+.66*D,.80*H);b.parent=eb['Spine']
    e=eb.new('Wing'+side+'End');e.head=b.tail;e.tail=e.head+Vector((0,0,.01));e.parent=b
bpy.ops.object.mode_set(mode='OBJECT')
groups={s:body.vertex_groups.new(name='Wing'+s) for s in ['Left','Right']};counts={'Left':0,'Right':0}
for v in body.data.vertices:
    p=v.co
    if abs(p.x)<=.28*W or p.y<=cut or p.z<.25*H:continue
    strength=min((abs(p.x)-.28*W)/(.25*W),1)*min((p.y-cut)/(.08*D),1)
    if strength<=0:continue
    for g in list(v.groups):body.vertex_groups[g.group].add([v.index],g.weight*(1-strength),'REPLACE')
    side='Left' if p.x>0 else 'Right';groups[side].add([v.index],strength,'REPLACE');counts[side]+=1
assert min(counts.values())>100, 'Review wing regions; never ship a rig with missing wing weights.'
base=B.sample(arm,bpy.data.actions['idle'],0)
for act in list(bpy.data.actions):
    if act.name not in ['idle','walk','walk_slow','run','hurt','death']:bpy.data.actions.remove(act)
for n in ['idle','walk','walk_slow','run','hurt','death']:
    if n not in bpy.data.actions:continue
    old=bpy.data.actions[n];poses=[];last=int(old.frame_range[1])
    for f in range(last+1):
        t=f/max(last,1);p=B.sample(arm,old,f);B.apply(arm,p)
        for side,sign in [('Left',1),('Right',-1)]:
            angle=sign*(8*math.sin(t*math.tau) if n not in ['hurt','death'] else 25*min(t*1.5,1))
            B.rot_world(arm,'Wing'+side,Quaternion(Vector((0,1,0)),math.radians(angle)))
        poses.append(B.grab(arm))
    B.write_action(arm,n,B.fix_quat_continuity(poses))
base=B.sample(arm,bpy.data.actions['idle'],0)
def strike(t):
    B.apply(arm,base);k=math.sin(t*math.pi)
    B.rot_world(arm,'RightArm',Quaternion(Vector((1,0,0)),math.radians(-60)*k));B.rot_world(arm,'LeftArm',Quaternion(Vector((1,0,0)),math.radians(-24)*k))
    for s,sign in [('Left',1),('Right',-1)]:B.rot_world(arm,'Wing'+s,Quaternion(Vector((0,1,0)),math.radians(sign*18)*k))
    return B.grab(arm)
for n,total in [('attack',18),('skill',24)]:B.write_action(arm,n,B.fix_quat_continuity([strike(f/total) for f in range(total+1)]))
B.assign(arm,bpy.data.actions['idle']);bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(0)
(out/'review/wing_rig_v001.json').write_text(json.dumps({'wing_vertices':counts,'bind_dimensions':[2*W,D,H]},indent=2))
bpy.ops.wm.save_as_mainfile(filepath=str(master));bpy.ops.export_scene.gltf(filepath=str(out/'gargoyle_v002.glb'),export_format='GLB',export_animation_mode='ACTIONS')
