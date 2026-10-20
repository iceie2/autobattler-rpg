"""Split the preserved segmented serpent into head, four body pieces, tail.
Each part has a minimal rigid skin and clips; no new paid generation.
"""
import bpy, os, math
from mathutils import Vector, Quaternion
ROOT='assets/3d pipeline/enemy/tempest_conduit'
parts=[('head','Head'),('body_1','Segment_5'),('body_2','Segment_4'),('body_3','Segment_3'),('body_4','Segment_2'),('tail','Segment_0')]
for role,bone in parts:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.abspath(ROOT+'/tempest_conduit_v003.glb'))
    originals=[]
    for o in bpy.data.objects:
        if o.type!='MESH' or o.name.startswith('Lightning_Link'):continue
        g=o.vertex_groups.get(bone)
        if g and any(any(x.group==g.index and x.weight>.9 for x in v.groups) for v in o.data.vertices): originals.append(o)
    verts_world=[o.matrix_world@v.co for o in originals for v in o.data.vertices]
    # Import converts axes with the armature's transform. Use world vertices.
    low=min(v.z for v in verts_world); centre=sum(verts_world,Vector())/len(verts_world)
    offset=Vector((centre.x,centre.y,low))
    kept=[]
    for o in originals:
        vertices=[o.matrix_world@v.co-offset for v in o.data.vertices]
        mesh=o.data.copy()
        for v,co in zip(mesh.vertices,vertices):v.co=co
        obj=bpy.data.objects.new(o.name+'_Part',mesh);bpy.context.collection.objects.link(obj);kept.append(obj)
    for o in list(bpy.data.objects):
        if o not in kept:bpy.data.objects.remove(o,do_unlink=True)
    data=bpy.data.armatures.new('PartRig');arm=bpy.data.objects.new('Tempest_'+role,data)
    bpy.context.collection.objects.link(arm);bpy.context.view_layer.objects.active=arm;arm.select_set(True)
    bpy.ops.object.mode_set(mode='EDIT')
    b=data.edit_bones.new('Hips');b.head=(0,0,0);b.tail=(0,0,.2)
    # Model3DSprite frames skinned characters from bone bounds. A single
    # Hips origin has zero height and puts the camera inside the geometry.
    # Bounds bones follow Hips, enclosing the actual part in every clip.
    points=[v.co for o in kept for v in o.data.vertices]
    lo=Vector(tuple(min(v[i] for v in points) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
    for n in range(8):
        marker=data.edit_bones.new('Bounds_'+str(n))
        marker.head=Vector(tuple(hi[i] if n&(1<<i) else lo[i] for i in range(3)))
        marker.tail=marker.head+Vector((0,0,.01));marker.parent=b
    bpy.ops.object.mode_set(mode='OBJECT')
    for o in kept:
        g=o.vertex_groups.new(name='Hips');g.add(list(range(len(o.data.vertices))),1,'REPLACE')
        mod=o.modifiers.new('RigidSkin','ARMATURE');mod.object=arm;o.parent=arm
    arm.animation_data_create();bpy.context.scene.render.fps=30
    for name,frames in [('idle',60),('walk',30),('attack',27),('skill',42),('ult',51),('hurt',15),('death',45)]:
        act=bpy.data.actions.new(name);arm.animation_data.action=act
        for f in range(frames+1):
            t=f/frames;p=arm.pose.bones['Hips'];p.rotation_mode='QUATERNION'
            z=.025*math.sin(t*math.tau);pitch=0;size=1
            if name=='walk':z=.04*math.sin(t*math.tau);pitch=.08*math.sin(t*math.tau)
            elif name=='attack':pitch=-.30*max(0,1-abs(t-.4)/.35)
            elif name in ('skill','ult'):
                contact=1.1 if name=='skill' else 1.4;clock=f/30
                charge=min(clock/contact,1);release=max(0,1-abs(clock-contact-.08)/.2) if clock>=contact else 0
                z=.08*charge;pitch=.22*charge-.45*release
            elif name=='hurt':pitch=.15*math.sin(t*math.pi)
            elif name=='death':pitch=1.3*t;size=1-.35*t;z=-.04*t
            p.location=(0,0,z);p.rotation_quaternion=Quaternion((1,0,0),pitch);p.scale=(size,)*3
            for prop in ('location','rotation_quaternion','scale'):p.keyframe_insert(prop,frame=f)
        tr=arm.animation_data.nla_tracks.new();tr.name=name;tr.strips.new(name,0,act);arm.animation_data.action=None
    p=arm.pose.bones['Hips'];p.location=(0,0,0);p.rotation_quaternion=Quaternion();p.scale=(1,)*3
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(ROOT+'/source/tempest_'+role+'_v004.blend'))
    bpy.ops.export_scene.gltf(filepath=os.path.abspath(ROOT+'/tempest_'+role+'_v004.glb'),export_format='GLB',export_animations=True)
    print('SNAKE_PART',role,len(kept))
