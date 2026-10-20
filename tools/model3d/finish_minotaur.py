"""Rigid socket axe and a horn-first Gore Rush on the generated shared body."""
import bpy,sys,pathlib,math
from mathutils import Vector,Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'assets/3d pipeline/enemy/goblin/review'))
import pose_lib as B
out=ROOT/'assets/3d pipeline/enemy/minotaur'
for d in ('source','review'):(out/d).mkdir(exist_ok=True);(out/d/'.gdignore').touch()
master=out/'source/minotaur_master_v001.blend';assert not master.exists()
arm=B.load(str(out/'raw/history/minotaur_v001.glb'));base=B.sample(arm,bpy.data.actions['idle'],0)
for act in list(bpy.data.actions):
    if act.name not in ('idle','walk','walk_slow','run','hurt','death'):bpy.data.actions.remove(act)
B.apply(arm,base);target=B.hw(arm,'RightArm')+Vector((-.30,-.19,-.40))
B.two_bone(arm,'RightArm','RightForeArm','RightHand',target,Vector((-1,0,-.2)));base=B.grab(arm);grip=B.hw(arm,'RightHand')
bpy.context.view_layer.objects.active=arm;bpy.ops.object.mode_set(mode='EDIT');bone=arm.data.edit_bones.new('weapon_r');bone.head=arm.data.edit_bones['RightHand'].head;bone.tail=bone.head+Vector((0,0,.03));bone.parent=arm.data.edit_bones['RightHand'];bpy.ops.object.mode_set(mode='OBJECT')
base=B.grab(arm);to_rest=arm.matrix_world@arm.data.bones['weapon_r'].matrix_local@arm.pose.bones['weapon_r'].matrix.inverted()@arm.matrix_world.inverted()
def mat(n,c,glow=False):
    m=bpy.data.materials.new(n);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=.78
    if glow:p.inputs['Emission Color'].default_value=(*c,1);p.inputs['Emission Strength'].default_value=.9
    return m
wood=mat('Axe_Wood',(.25,.10,.035));steel=mat('Axe_Steel',(.10,.07,.06));edge=mat('Axe_Ember',(1,.28,.025),True);parts=[]
def shaft(a,b,r,material):
    a,b=grip+Vector(a),grip+Vector(b);bpy.ops.mesh.primitive_cone_add(vertices=10,radius1=r,radius2=r,depth=(b-a).length,location=(a+b)/2)
    ob=bpy.context.object;ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();bpy.ops.object.transform_apply(location=False,rotation=True,scale=True);ob.data.materials.append(material);parts.append(ob)
shaft((0,0,-.39),(0,0,.73),.032,wood)
outline=[(-.045,.70),(-.25,.77),(-.37,.70),(-.29,.46),(-.20,.40),(-.045,.54)]
for sign in [-1,1]:
    pts=[(sign*x,z) for x,z in outline];verts=[tuple(grip+Vector((x,y,z))) for y in [-.035,.035] for x,z in pts];n=len(pts)
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new('AxeBlade');mesh.from_pydata(verts,[],faces);mesh.update();ob=bpy.data.objects.new('Blade',mesh);bpy.context.collection.objects.link(ob);ob.data.materials.append(steel);parts.append(ob)
    for i,j in [(1,2),(2,3),(3,4)]:shaft((pts[i][0],-.038,pts[i][1]),(pts[j][0],-.038,pts[j][1]),.010,edge)
bpy.ops.object.select_all(action='DESELECT')
for ob in parts:ob.select_set(True)
bpy.context.view_layer.objects.active=parts[0];bpy.ops.object.join();axe=bpy.context.object;axe.name='Axe_Held';world=axe.matrix_world.copy()
for v in axe.data.vertices:v.co=to_rest@world@v.co
axe.matrix_world.identity();g=axe.vertex_groups.new(name='weapon_r');g.add(list(range(len(axe.data.vertices))),1,'REPLACE');mod=axe.modifiers.new('Rigid axe','ARMATURE');mod.object=arm;axe.parent=arm;axe.matrix_parent_inverse=arm.matrix_world.inverted()
def pose(t,skill):
    B.apply(arm,base);k=math.sin(t*math.pi)
    if skill:
        B.rot_world(arm,'Head',Quaternion(Vector((1,0,0)),math.radians(32)*k))
        B.rot_world(arm,'Spine',Quaternion(Vector((1,0,0)),math.radians(15)*k))
    else:B.rot_world(arm,'RightArm',Quaternion(Vector((1,0,0)),math.radians(-50)*k))
    return B.grab(arm)
for n,total in [('attack',18),('skill',24)]:B.write_action(arm,n,B.fix_quat_continuity([pose(f/total,n=='skill') for f in range(total+1)]))
for n in ['idle','walk','run','walk_slow']:
    if n not in bpy.data.actions:continue
    old=bpy.data.actions[n];poses=[]
    for f in range(int(old.frame_range[1])+1):
        p=B.sample(arm,old,f)
        for b in ['RightArm','RightForeArm','RightHand','weapon_r']:p[b]=base[b]
        poses.append(p)
    B.write_action(arm,n,B.fix_quat_continuity(poses))
B.assign(arm,bpy.data.actions['idle']);bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(0)
bpy.ops.wm.save_as_mainfile(filepath=str(master));bpy.ops.export_scene.gltf(filepath=str(out/'minotaur_v002.glb'),export_format='GLB',export_animation_mode='ACTIONS')
