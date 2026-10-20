"""Replace borrowed weapon swings with unarmed family actions; preserve free locomotion."""
import bpy,sys,pathlib,math
from mathutils import Vector,Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'assets/3d pipeline/enemy/goblin/review'))
import pose_lib as B
name=sys.argv[-1];assert name in ('orc','troll','ogre')
out=ROOT/'assets/3d pipeline/enemy'/name
for d in ('source','review'):(out/d).mkdir(exist_ok=True);(out/d/'.gdignore').touch()
master=out/f'source/{name}_master_v001.blend';assert not master.exists()
arm=B.load(str(out/f'raw/history/{name}_v001.glb'));base=B.sample(arm,bpy.data.actions['idle'],0)
for a in list(bpy.data.actions):
    if a.name not in ('idle','walk','run','walk_slow','hurt','death'):bpy.data.actions.remove(a)
def pose(t,skill):
    B.apply(arm,base)
    pulse=math.sin(t*math.pi)
    if skill and name=='troll':
        for side in ('Right','Left'):
            B.rot_world(arm,side+'Arm',Quaternion(Vector((1,0,0)),math.radians(-48)*pulse))
            B.rot_world(arm,side+'ForeArm',Quaternion(Vector((0,0,1)),math.radians(18 if side=='Right' else -18)*pulse))
        B.rot_world(arm,'Head',Quaternion(Vector((1,0,0)),math.radians(-16)*pulse))
    else:
        for side in (('Right','Left') if skill else ('Right',)):
            B.rot_world(arm,side+'Arm',Quaternion(Vector((1,0,0)),math.radians(-65 if skill else -36)*pulse))
            B.rot_world(arm,side+'ForeArm',Quaternion(Vector((0,0,1)),math.radians(25 if side=='Right' else -25)*pulse))
        B.rot_world(arm,'Head',Quaternion(Vector((1,0,0)),math.radians(9)*pulse))
    return B.grab(arm)
for n,total in [('attack',15),('skill',24)]:B.write_action(arm,n,B.fix_quat_continuity([pose(f/total,n=='skill') for f in range(total+1)]))
B.assign(arm,bpy.data.actions['idle']);bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(master))
bpy.ops.export_scene.gltf(filepath=str(out/f'{name}_v002.glb'),export_format='GLB',export_animation_mode='ACTIONS')
