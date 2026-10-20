"""Measured creature rigs from generated bodies, with a separately weighted tail."""
import bpy,sys,pathlib,math,json
from mathutils import Vector
ROOT=pathlib.Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools/model3d'))
import creature_rig as C
name=sys.argv[-1];assert name in ('hellhound','sky_wyvern','harpy','gargoyle')
out=ROOT/'assets/3d pipeline/enemy'/name
for d in ('source','review'):(out/d).mkdir(exist_ok=True);(out/d/'.gdignore').touch()
version=2 if name=='hellhound' else 1
master=out/f'source/{name}_master_v{version:03}.blend';assert not master.exists()
body=C.load_body(str(out/f'raw/{name}_body_v001.glb'))
if name=='hellhound':
    arm,L,clips=C.rig_quad(body)
    # The wolf's sculpted open muzzle is not the anglerfish jaw this generic rig expects.
    # Keep the muzzle rigid to the head instead of stretching the whole snout in a roar.
    jaw=body.vertex_groups.get('Jaw');head=body.vertex_groups.get('Head')
    for v in body.data.vertices:
        weights={g.group:g.weight for g in v.groups}
        if jaw.index in weights:
            head.add([v.index],weights[jaw.index]+weights.get(head.index,0),'REPLACE')
            jaw.remove([v.index])
else:arm,L,clips=C.rig_bird(body,True,True)
V=[v.co.copy() for v in body.data.vertices];H=max(v.z for v in V);cut=None
bpy.context.view_layer.objects.active=arm;bpy.ops.object.mode_set(mode='EDIT');eb=arm.data.edit_bones
if name=='hellhound':
    lo=min(v.y for v in V);hi=max(v.y for v in V);cut=lo+.76*(hi-lo)
    pts=[v for v in V if v.y>cut and v.z>.25*H]
    if len(pts)>20:
        root=Vector((0,cut,.53*H));tip=max(pts,key=lambda p:(p-root).length).copy();mid=root.lerp(tip,.5)
        for n,h,t,parent in [('Tail0',root,mid,'Hips'),('Tail1',mid,tip,'Tail0')]:
            b=eb.new(n);b.head=h;b.tail=t;b.parent=eb[parent]
    else:cut=None
for n,p in [('BoundsBase',Vector((0,0,0))),('BoundsTop',Vector((0,0,H)))]:
    b=eb.new(n);b.head=p;b.tail=p+Vector((0,0,.01));b.parent=eb['Hips']
bpy.ops.object.mode_set(mode='OBJECT')
if cut is not None:
    g0=body.vertex_groups.new(name='Tail0');g1=body.vertex_groups.new(name='Tail1')
    for v in body.data.vertices:
        if v.co.y>cut and v.co.z>.25*H:
            for g in list(v.groups):body.vertex_groups[g.group].remove([v.index])
            t=min(max((v.co.y-cut)/(hi-cut),0),1);g0.add([v.index],1-t,'REPLACE');g1.add([v.index],t,'REPLACE')
    for i,(n,frames,fn) in enumerate(clips):
        def wrapped(t,fn=fn):
            spec=fn(t);spec.update({'Tail0':(C.Z,4*math.sin(t*math.tau)),'Tail1':(C.Z,7*math.sin(t*math.tau-.7))});return spec
        clips[i]=(n,frames,wrapped)
bpy.context.scene.render.fps=30
for n,f,fn in clips:C.Clip(arm,n,f).bake(fn)
ad=arm.animation_data;ad.action=bpy.data.actions['idle'];ad.action_slot=ad.action.slots[0];bpy.context.scene.frame_set(0)
report={'family':name,'landmarks':{k:list(v) if isinstance(v,Vector) else v for k,v in L.items()},'bones':[b.name for b in arm.data.bones],'unweighted':sum(not any(g.weight>0 for g in v.groups) for v in body.data.vertices),'clips':[c[0] for c in clips]}
(out/f'review/rig_v{version:03}.json').write_text(json.dumps(report,indent=2));assert report['unweighted']==0
bpy.ops.wm.save_as_mainfile(filepath=str(master));bpy.ops.export_scene.gltf(filepath=str(out/f'{name}_v{version:03}.glb'),export_format='GLB',export_animation_mode='ACTIONS')
