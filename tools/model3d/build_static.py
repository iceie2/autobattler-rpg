"""Build Static's stylized low-poly 3D production model with core clips."""
import math
import os
import sys
import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[argv.index("--out") + 1]
blend = argv[argv.index("--save-blend") + 1]

bpy.ops.wm.read_factory_settings(use_empty=True)

def mat(name, color, metallic=0.0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.metallic = metallic
    m.roughness = 0.72
    return m

YELLOW=mat("DuckYellow",(1.0,.55,.015)); ORANGE=mat("BillOrange",(.95,.20,.025))
BROWN=mat("Leather",(.20,.075,.035)); STEEL=mat("Steel",(.20,.29,.32),.45)
DARK=mat("DarkRubber",(.025,.035,.04)); CYAN=mat("ElectricCyan",(.01,.85,1.0),.2)
WHITE=mat("EyeWhite",(.72,.92,.90)); BLACK=mat("Pupil",(.005,.008,.01))

def cube(name, loc, scale, material, bevel=.08):
    bpy.ops.mesh.primitive_cube_add(location=loc); o=bpy.context.object; o.name=name
    o.scale=scale; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=o.modifiers.new("Rounded","BEVEL"); mod.width=bevel; mod.segments=2
    o.data.materials.append(material); return o

def sphere(name, loc, scale, material):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=10, location=loc)
    o=bpy.context.object; o.name=name; o.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    o.data.materials.append(material); return o

def cyl(name, loc, radius, depth, material, rot=(0,0,0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth, location=loc, rotation=rot)
    o=bpy.context.object; o.name=name; o.data.materials.append(material); return o

def bone_parent(obj, arm, bone):
    world = obj.matrix_world.copy()
    obj.parent=arm; obj.parent_type='BONE'; obj.parent_bone=bone
    obj.matrix_world = world

# Clean, human-scale rig.
bpy.ops.object.armature_add(enter_editmode=True, location=(0,0,0))
arm=bpy.context.object; arm.name="StaticRig"; eb=arm.data.edit_bones; eb.remove(eb[0])
def addbone(name, head, tail, parent=None):
    b=eb.new(name); b.head=head; b.tail=tail
    if parent: b.parent=eb[parent]
    return b
addbone("Hips",(0,0,.72),(0,0,1.02)); addbone("Spine",(0,0,1.02),(0,0,1.42),"Hips")
addbone("Head",(0,0,1.42),(0,0,1.78),"Spine")
addbone("LeftArm",(.28,0,1.35),(.62,0,1.15),"Spine"); addbone("RightArm",(-.28,0,1.35),(-.62,0,1.15),"Spine")
addbone("LeftLeg",(.18,0,.72),(.18,0,.22),"Hips"); addbone("RightLeg",(-.18,0,.72),(-.18,0,.22),"Hips")
bpy.ops.object.mode_set(mode='OBJECT')

parts=[]
parts += [sphere("Body",(0,0,1.02),(.48,.30,.62),YELLOW), sphere("Head",(0,-.01,1.62),(.43,.34,.39),YELLOW)]
parts += [cube("Bill",(0,-.39,1.55),(.34,.18,.10),ORANGE,.1), cube("LowerBill",(0,-.43,1.48),(.28,.13,.055),ORANGE,.06)]
# Goggles and eyes.
for x in (-.19,.19):
    parts += [cyl("Goggle",(x,-.325,1.76),.19,.10,STEEL,(math.pi/2,0,0)),
              cyl("Lens",(x,-.382,1.76),.135,.015,WHITE,(math.pi/2,0,0)),
              cyl("Pupil",(x,-.397,1.76),.047,.018,BLACK,(math.pi/2,0,0))]
parts += [cube("GoggleBridge",(0,-.36,1.76),(.075,.045,.035),BROWN,.025)]
# Overalls bib, straps, belt and buckle.
parts += [cube("Bib",(0,-.285,1.08),(.30,.045,.31),BROWN,.04), cube("Belt",(0,-.31,.83),(.42,.055,.075),BROWN,.025),
          cube("Buckle",(0,-.375,.83),(.105,.025,.095),STEEL,.025)]
for x in (-.24,.24): parts.append(cube("Strap",(x,-.30,1.31),(.055,.04,.28),BROWN,.02))
# Arms/gloves and legs/boots, grouped to bones.
for side,x in (("Left",.47),("Right",-.47)):
    armobj=cyl(side+"Sleeve",(x,0,1.12),.17,.50,YELLOW,(0,math.pi/2,0)); parts.append(armobj); bone_parent(armobj,arm,side+"Arm")
    glove=sphere(side+"Glove",((.72 if x>0 else -.72),-.03,1.05),(.22,.20,.24),ORANGE); parts.append(glove); bone_parent(glove,arm,side+"Arm")
for side,x in (("Left",.19),("Right",-.19)):
    leg=cyl(side+"Leg",(x,0,.48),.16,.48,DARK); parts.append(leg); bone_parent(leg,arm,side+"Leg")
    boot=cube(side+"Boot",(x,-.12,.18),(.25,.34,.14),ORANGE,.10); parts.append(boot); bone_parent(boot,arm,side+"Leg")
# Wrench and sparking wire establish the mechanic read.
wrench=cube("Wrench",(.61,-.08,1.03),(.055,.04,.30),STEEL,.02); wrench.rotation_euler[1]=-.45; parts.append(wrench); bone_parent(wrench,arm,"LeftArm")
wire=cyl("LiveWire",(-.72,-.08,1.30),.025,.52,DARK,(0.2,.8,0)); parts.append(wire); bone_parent(wire,arm,"RightArm")
for i in range(5):
    spark=sphere("Spark%02d"%i,(-.88+i*.08,-.12,1.52+(.06 if i%2 else 0)),(.035,.025,.035),CYAN); parts.append(spark); bone_parent(spark,arm,"RightArm")

# Parent torso/head rigidly to their bones.
for o in parts:
    if o.parent: continue
    if o.name.startswith(("Head","Bill","LowerBill","Goggle","Lens","Pupil")) or o.name=="GoggleBridge": bone_parent(o,arm,"Head")
    elif o.name not in ("Body",): bone_parent(o,arm,"Spine")
bone_parent(bpy.data.objects["Body"],arm,"Spine")

def action(name, length, poses):
    a=bpy.data.actions.new(name); a.use_fake_user=True
    arm.animation_data_create(); arm.animation_data.action=a
    for frame,bone,axis,degrees in poses:
        pb=arm.pose.bones[bone]; pb.rotation_mode='XYZ'; pb.rotation_euler[axis]=math.radians(degrees)
        pb.keyframe_insert("rotation_euler",frame=frame,group=bone)
    # Ensure every clip has explicit stable Hips keys and its intended range.
    arm.pose.bones["Hips"].location=Vector((0,0,0)); arm.pose.bones["Hips"].keyframe_insert("location",frame=0,group="Hips"); arm.pose.bones["Hips"].keyframe_insert("location",frame=length,group="Hips")
    a.frame_start=0; a.frame_end=length
    for pb in arm.pose.bones: pb.rotation_euler=(0,0,0); pb.location=(0,0,0)

action("idle",48,[(0,"Head",2,-3),(24,"Head",2,3),(48,"Head",2,-3),(0,"LeftArm",1,-4),(24,"LeftArm",1,4),(48,"LeftArm",1,-4)])
action("walk",24,[(0,"LeftLeg",0,24),(0,"RightLeg",0,-24),(12,"LeftLeg",0,-24),(12,"RightLeg",0,24),(24,"LeftLeg",0,24),(24,"RightLeg",0,-24),(0,"LeftArm",0,-18),(12,"LeftArm",0,18),(24,"LeftArm",0,-18)])
action("attack",18,[(0,"LeftArm",0,0),(5,"LeftArm",0,-65),(9,"LeftArm",0,55),(13,"LeftArm",0,62),(18,"LeftArm",0,0),(0,"Spine",2,0),(9,"Spine",2,-12),(18,"Spine",2,0)])
action("hurt",14,[(0,"Spine",0,0),(4,"Spine",0,-20),(8,"Spine",0,10),(14,"Spine",0,0)])
action("death",24,[(0,"Hips",2,0),(12,"Hips",2,58),(24,"Hips",2,88)])
action("skill",24,[(0,"RightArm",0,0),(6,"RightArm",0,-75),(14,"RightArm",0,-75),(24,"RightArm",0,0),(0,"Head",2,0),(12,"Head",2,-10),(24,"Head",2,0)])
action("ult",30,[(0,"LeftArm",0,0),(8,"LeftArm",0,-80),(18,"LeftArm",0,-80),(30,"LeftArm",0,0),(0,"RightArm",0,0),(8,"RightArm",0,-80),(18,"RightArm",0,-80),(30,"RightArm",0,0)])

bpy.context.scene.render.fps=24
os.makedirs(os.path.dirname(blend),exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=blend)
bpy.ops.export_scene.gltf(filepath=out,export_format='GLB',export_animations=True,export_skins=True)
print("WROTE",blend,"AND",out)
