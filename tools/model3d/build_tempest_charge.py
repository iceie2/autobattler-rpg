import bpy, math, os
from mathutils import Quaternion
bpy.ops.wm.read_factory_settings(use_empty=True)
root='assets/3d pipeline/enemy/tempest_conduit'
bpy.ops.import_scene.gltf(filepath=os.path.abspath(root+'/tempest_conduit_v001.glb'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
print('TEMPest bones:', [b.name for b in arm.pose.bones])
arm.animation_data_create()
# Keep imported clips; replace only the cast with a deliberate held coil and
# a fast forward release at the channel's 0.9-second contact frame.
for tr in list(arm.animation_data.nla_tracks):
    if any(st.action and st.action.name.lower().split('.')[0]=='skill' for st in tr.strips):
        arm.animation_data.nla_tracks.remove(tr)
arm.animation_data.action=None
action=bpy.data.actions.new('skill')
arm.animation_data.action=action
bpy.context.scene.render.fps=30
necks=[p for p in arm.pose.bones if 'neck' in p.name.lower()]
for f in range(40):
    t=f/30
    charge=min(t/.9,1)
    release=max(0,1-abs(t-.98)/.22) if t>=.9 else 0
    for i,p in enumerate(necks):
        p.rotation_mode='QUATERNION'
        p.rotation_quaternion=Quaternion((1,0,0),math.radians((-14*charge+34*release)*(0.7+i*.18)))
        p.keyframe_insert('rotation_quaternion',frame=f)
track=arm.animation_data.nla_tracks.new(); track.name='skill'
track.strips.new('skill',0,action)
arm.animation_data.action=None
action=bpy.data.actions.new('ult')
arm.animation_data.action=action
for f in range(40):
    t=f/30
    charge=min(t/.9,1)
    release=max(0,1-abs(t-.98)/.22) if t>=.9 else 0
    for i,p in enumerate(necks):
        p.rotation_mode='QUATERNION'
        p.rotation_quaternion=Quaternion((1,0,0),math.radians((-23*charge+45*release)*(0.7+i*.15))) @ Quaternion((0,0,1),math.radians(12*math.sin(t*12)*charge))
        p.keyframe_insert('rotation_quaternion',frame=f)
track=arm.animation_data.nla_tracks.new(); track.name='ult'
track.strips.new('ult',0,action)
arm.animation_data.action=None
for p in arm.pose.bones: p.rotation_quaternion=Quaternion()
os.makedirs(root+'/source',exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(root+'/source/tempest_conduit_v002.blend'))
bpy.ops.export_scene.gltf(filepath=os.path.abspath(root+'/tempest_conduit_v002.glb'),export_format='GLB',export_animations=True)
