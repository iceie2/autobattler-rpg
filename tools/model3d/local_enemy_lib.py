"""Shared Blender construction utilities, each family supplies its own silhouette and motion."""
import bpy, math, pathlib
from mathutils import Vector, Quaternion
ROOT=pathlib.Path(__file__).resolve().parents[2]
class Asset:
    def __init__(self,name,bones,version=1):
        self.name=name;self.version=version;self.out=ROOT/'assets/3d pipeline/enemy'/name
        for d in ('source','raw','review'):
            (self.out/d).mkdir(parents=True,exist_ok=True);(self.out/d/'.gdignore').touch()
        self.master=self.out/f'source/{name}_master_v{version:03}.blend'
        assert not self.master.exists(), 'Increment version, preserve masters.'
        bpy.ops.wm.read_factory_settings(use_empty=True);self.parts=[]
        data=bpy.data.armatures.new(name+'Rig');self.arm=bpy.data.objects.new('Armature',data);bpy.context.collection.objects.link(self.arm)
        bpy.context.view_layer.objects.active=self.arm;self.arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
        for n,h,t,p in bones:
            b=data.edit_bones.new(n);b.head=h;b.tail=t
            if p:b.parent=data.edit_bones[p]
        bpy.ops.object.mode_set(mode='OBJECT');self.arm.select_set(False)
    def mat(self,n,c,roughness=.75,metallic=0):
        m=bpy.data.materials.new(n);m.use_nodes=True;m.diffuse_color=(*c,1)
        p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*c,1);p.inputs['Roughness'].default_value=roughness;p.inputs['Metallic'].default_value=metallic
        return m
    def bind(self,ob,n,b,m,smooth=True):
        ob.name=n;ob.data.materials.append(m);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        g=ob.vertex_groups.new(name=b);g.add(list(range(len(ob.data.vertices))),1,'REPLACE')
        for p in ob.data.polygons:p.use_smooth=smooth
        self.parts.append(ob)
    def ball(self,n,c,s,b,m):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=10,location=c);ob=bpy.context.object;ob.scale=s;self.bind(ob,n,b,m)
    def tube(self,n,a,b,r1,r2,bone,m,vertices=12):
        a,b=Vector(a),Vector(b);bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=r1,radius2=r2,depth=(b-a).length,location=(a+b)/2)
        ob=bpy.context.object;ob.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler();self.bind(ob,n,bone,m)
    def box(self,n,c,s,b,m,bevel=.025):
        bpy.ops.mesh.primitive_cube_add(size=1,location=c);ob=bpy.context.object;ob.scale=s
        bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        if bevel:
            mod=ob.modifiers.new('Soft edges','BEVEL');mod.width=bevel;mod.segments=2
            bpy.ops.object.modifier_apply(modifier=mod.name)
        self.bind(ob,n,b,m,False)
    def torus(self,n,c,r,minor,b,m,rotation=(math.pi/2,0,0)):
        bpy.ops.mesh.primitive_torus_add(major_segments=24,minor_segments=8,location=c,major_radius=r,minor_radius=minor,rotation=rotation)
        self.bind(bpy.context.object,n,b,m)
    def join(self):
        bpy.ops.object.select_all(action='DESELECT')
        for ob in self.parts:ob.select_set(True)
        bpy.context.view_layer.objects.active=self.parts[0];bpy.ops.object.join();self.body=bpy.context.object;self.body.name=self.name.title()+'Body'
        mod=self.body.modifiers.new('Skin','ARMATURE');mod.object=self.arm;self.body.parent=self.arm
    def action(self,n,frames,fn):
        a=bpy.data.actions.new(n);a.use_fake_user=True;ad=self.arm.animation_data_create();ad.action=a
        for f in range(frames+1):
            spec=fn(f/frames)
            for pb in self.arm.pose.bones:
                axis=pb.bone.matrix_local.to_3x3().inverted();val=spec.get(pb.name,0)
                direction=Vector((1,0,0));angle=val;offset=(0,0,0);scale=(1,1,1)
                if isinstance(val,dict):
                    direction=Vector(val.get('axis',(1,0,0)));angle=val.get('angle',0);offset=val.get('offset',(0,0,0));scale=val.get('scale',(1,1,1))
                pb.rotation_mode='QUATERNION';pb.rotation_quaternion=Quaternion(axis@direction,math.radians(angle));pb.location=axis@Vector(offset);pb.scale=scale
                for p in ('rotation_quaternion','location','scale'):pb.keyframe_insert(p,frame=f)
        if a.slots:ad.action_slot=a.slots[0]
    def export(self):
        ad=self.arm.animation_data;ad.action=bpy.data.actions['idle'];ad.action_slot=ad.action.slots[0]
        bpy.context.scene.render.fps=30;bpy.context.scene.frame_set(0)
        bpy.ops.wm.save_as_mainfile(filepath=str(self.master))
        bpy.ops.export_scene.gltf(filepath=str(self.out/f'{self.name}_v{self.version:03}.glb'),export_format='GLB',export_animation_mode='ACTIONS')
