import bpy,sys,pathlib,json
ROOT=pathlib.Path(__file__).resolve().parents[2];name=sys.argv[-1]
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(ROOT/f'assets/3d pipeline/enemy/{name}/{name}_v001.glb'))
arm=next(o for o in bpy.data.objects if o.type=='ARMATURE')
body=max((o for o in bpy.data.objects if o.type=='MESH'),key=lambda o:len(o.data.vertices))
coords=[v.co for v in body.data.vertices]
print('RIG_INSPECTION',json.dumps({'body_scale':list(body.matrix_world.to_scale()),'arm_scale':list(arm.matrix_world.to_scale()),'mesh_ranges':[[min(v[i] for v in coords),max(v[i] for v in coords)] for i in range(3)],'bone_rest_head':list(arm.data.bones['Head'].head_local),'bone_pose_head':list(arm.pose.bones['Head'].head)}))
