"""Local Blender build: floating armored serpent and seven authored clips.
Preserves v001/v002. Rigid pieces are skinned to their own bones, not bone-parented.
Run from project root: blender -b --python tools/model3d/build_tempest_living_storm.py
"""
import bpy, math, os, json
from mathutils import Vector, Quaternion

bpy.ops.wm.read_factory_settings(use_empty=True)
ROOT = 'assets/3d pipeline/enemy/tempest_conduit'
os.makedirs(ROOT+'/source', exist_ok=True)
open(ROOT+'/source/.gdignore','w').close()

def material(name, color, metal=0, emission=0):
    m=bpy.data.materials.new(name); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Metallic'].default_value=metal
    p.inputs['Roughness'].default_value=.48
    p.inputs['Emission Color'].default_value=(*color,1)
    p.inputs['Emission Strength'].default_value=emission
    return m

armor=material('Storm_Obsidian',(.075,.105,.16),.25)
edge=material('Silver_Armor_Edges',(.32,.43,.56),.5)
light=material('Cyan_Current',(.08,.8,1),.1,2.2)
bone=material('Ivory_Fangs',(.65,.85,.88),.15)

# Tail flows around a loose S and rises into a solid forward-facing head.
centres=[Vector((1.55,.65,.23)),Vector((1.20,.20,.35)),Vector((.88,-.14,.49)),
         Vector((.49,-.24,.65)),Vector((.13,-.12,.85)),Vector((-.10,-.10,1.10))]
head=Vector((-.12,-.23,1.43))
arm_data=bpy.data.armatures.new('Tempest_Rig')
arm=bpy.data.objects.new('Tempest_Living_Storm',arm_data)
bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm; arm.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
hips=arm_data.edit_bones.new('Hips'); hips.head=(0,0,0); hips.tail=(0,0,.2)
for name,c in [(f'Segment_{i}',c) for i,c in enumerate(centres)]+[('Head',head)]:
    b=arm_data.edit_bones.new(name); b.head=c; b.tail=c+Vector((0,0,.14)); b.parent=hips
bpy.ops.object.mode_set(mode='OBJECT')

def bind(o,name,mat):
    o.data.materials.append(mat)
    bpy.context.view_layer.objects.active=o
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    g=o.vertex_groups.new(name=name); g.add(list(range(len(o.data.vertices))),1,'REPLACE')
    mod=o.modifiers.new('RigidSkin','ARMATURE'); mod.object=arm; o.parent=arm
    return o

def shell(name,loc,scale,mat,rig):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=6,location=loc)
    o=bpy.context.object; o.name=name; o.scale=scale
    return bind(o,rig,mat)

def spike(name,start,end,radius,mat,rig):
    d=Vector(end)-Vector(start)
    bpy.ops.mesh.primitive_cone_add(vertices=6,radius1=radius,radius2=.008,depth=d.length,location=(Vector(start)+Vector(end))/2)
    o=bpy.context.object; o.name=name; o.rotation_mode='QUATERNION'; o.rotation_quaternion=d.to_track_quat('Z','Y')
    return bind(o,rig,mat)

for i,c in enumerate(centres):
    n=f'Segment_{i}'; r=.10+i*.014
    shell(f'Floating_Armor_{i}',c,(r*1.45,r*1.25,r*.95),armor,n)
    shell(f'Core_{i}',c,(r*.72,r*.72,r*.75),light,n)
    # Paired flank plates and swept dorsal fin produce an armored silhouette.
    for side in (-1,1):
        shell(f'Rim_{i}_{side}',c+Vector((side*r*.83,0,.035)),(r*.38,r*.96,r*.68),edge,n)
    spike(f'Crest_{i}',c+Vector((0,.035,r*.55)),c+Vector((0,.11,r*1.8)),r*.5,edge,n)

# Angular skull with an extended wedge snout and open dark mouth.
vertices=[]
for y,w,top,bottom in [(.12,.26,.15,-.10),(-.18,.23,.20,-.08),(-.48,.14,.01,-.04)]:
    vertices.extend([head+Vector((-w,y,bottom)),head+Vector((w,y,bottom)),head+Vector((w*.85,y,top)),head+Vector((-w*.85,y,top))])
faces=[(0,3,2,1),(8,9,10,11)]
for j in range(2):
    for k in range(4): faces.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
mesh=bpy.data.meshes.new('AngularSkullMesh');mesh.from_pydata(vertices,[],faces);mesh.update()
skull=bpy.data.objects.new('Angular_Serpent_Head',mesh);bpy.context.collection.objects.link(skull)
bind(skull,'Head',armor)
shell('Mouth_Current',head+Vector((0,-.31,-.10)),(.12,.17,.03),light,'Head')
shell('Jaw',head+Vector((0,-.24,-.18)),(.18,.26,.048),armor,'Head')
for side in (-1,1):
    shell(f'Cheek_{side}',head+Vector((side*.22,-.04,-.02)),(.07,.19,.13),edge,'Head')
    shell(f'Eye_{side}',head+Vector((side*.207,-.18,.115)),(.025,.10,.025),light,'Head')
    shell(f'Front_Eye_{side}',head+Vector((side*.115,-.405,.075)),(.050,.025,.025),light,'Head')
    shell(f'Brow_{side}',head+Vector((side*.21,-.15,.17)),(.06,.17,.035),edge,'Head')
    spike(f'Horn_{side}',head+Vector((side*.17,.03,.13)),head+Vector((side*.30,.20,.42)),.072,edge,'Head')
    spike(f'Fang_{side}',head+Vector((side*.115,-.34,-.04)),head+Vector((side*.10,-.38,-.25)),.043,bone,'Head')
spike('Brow_Blade',head+Vector((0,-.13,.16)),head+Vector((0,-.37,.27)),.085,edge,'Head')

# Thin jagged current bridges use linear endpoint weights to both neighbors.
chain=centres+[head]
names=[f'Segment_{i}' for i in range(6)]+['Head']
for i,(a,b) in enumerate(zip(chain,chain[1:])):
    verts=[]; faces=[]; weights=[]
    d=b-a; sideways=d.cross(Vector((0,1,0))).normalized()
    for j in range(9):
        t=j/8; c=a.lerp(b,t)+sideways*(math.sin(j*2.3)*.055*math.sin(math.pi*t))
        for k in range(4):
            verts.append(c+Vector((math.cos(k*math.pi/2)*.026,math.sin(k*math.pi/2)*.026,0)))
            weights.append(t)
        if j:
            for k in range(4): faces.append(((j-1)*4+k,(j-1)*4+(k+1)%4,j*4+(k+1)%4,j*4+k))
    mesh=bpy.data.meshes.new(f'CurrentMesh_{i}'); mesh.from_pydata(verts,[],faces); mesh.update()
    o=bpy.data.objects.new(f'Lightning_Link_{i}',mesh); bpy.context.collection.objects.link(o)
    o.data.materials.append(light)
    g1=o.vertex_groups.new(name=names[i]); g2=o.vertex_groups.new(name=names[i+1])
    for vi,t in enumerate(weights):
        if t<1:g1.add([vi],1-t,'REPLACE')
        if t>0:g2.add([vi],t,'REPLACE')
    mod=o.modifiers.new('CurrentSkin','ARMATURE'); mod.object=arm; o.parent=arm

arm.animation_data_create(); bpy.context.scene.render.fps=30
clips=[('idle',60),('walk',30),('attack',27),('skill',42),('ult',51),('hurt',15),('death',45)]
for clip,frames in clips:
    action=bpy.data.actions.new(clip); arm.animation_data.action=action
    for f in range(frames+1):
        t=f/frames; clock=f/30
        for i,n in enumerate(names):
            p=arm.pose.bones[n]; p.rotation_mode='QUATERNION'; p.location=(0,0,0); p.scale=(1,1,1)
            wave=math.sin(2*math.pi*t-i*.65)
            yaw=.04*wave; pitch=0
            p.location=(.018*wave,0,.025*math.sin(2*math.pi*t-i*.7))
            if clip=='walk':
                p.location=(.095*wave,.045*math.cos(2*math.pi*t-i*.7),.05*math.sin(2*math.pi*t-i*.5)); yaw=.22*wave
            elif clip=='attack':
                hit=max(0,1-abs(t-.42)/.30); pitch=-.42*hit*(i/6)
                p.location=(.025*wave,-.20*hit*(i/6),.035*wave)
            elif clip in ('skill','ult'):
                # Skill contact at 1.1s, surge at 1.4s: body gathers then spreads.
                contact=1.1 if clip=='skill' else 1.4
                charge=min(clock/contact,1); release=max(0,1-abs(clock-contact-.08)/.20) if clock>=contact else 0
                pitch=.30*charge*(i/6)-.55*release*(i/6)
                p.location=(.06*math.sin(i*1.7)*charge,0,.10*charge+.05*wave)
                yaw=.10*math.sin(i+clock*6)*charge
            elif clip=='hurt': pitch=.2*math.sin(math.pi*t)
            elif clip=='death':
                p.location=(.22*math.sin(i*1.8)*t,.10*math.cos(i)*t,-chain[i].z*t*.85)
                pitch=.7*t; yaw=.4*math.sin(i)*t
            p.rotation_quaternion=Quaternion((0,0,1),yaw) @ Quaternion((1,0,0),pitch)
            for prop in ('location','rotation_quaternion','scale'):p.keyframe_insert(prop,frame=f)
    tr=arm.animation_data.nla_tracks.new(); tr.name=clip; tr.strips.new(clip,0,action)
    arm.animation_data.action=None
for p in arm.pose.bones:p.location=(0,0,0); p.rotation_quaternion=Quaternion(); p.scale=(1,1,1)
bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(ROOT+'/source/tempest_conduit_v003.blend'))
bpy.ops.export_scene.gltf(filepath=os.path.abspath(ROOT+'/tempest_conduit_v003.glb'),export_format='GLB',export_animations=True)
print('LIVING_STORM_BUILD:',json.dumps({'segments':6,'head':1,'current_links':6,'clips':[c[0] for c in clips]}))
