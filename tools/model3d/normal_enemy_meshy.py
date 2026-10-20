"""Explicit, resumable submissions through the existing authorized Meshy account."""
import pathlib, json, sys
import meshy_api as api
ROOT=pathlib.Path(__file__).resolve().parents[2]
REFERENCES={
 'harpy':ROOT/'assets/3d pipeline/enemy/harpy/raw/harpy_body_concept_v001.png',
 'gargoyle':ROOT/'assets/3d pipeline/enemy/gargoyle/raw/gargoyle_body_concept_v001.png',
 'tidepool_horror':ROOT/'assets/using/enemies/normal/tidepool_horror.png',
 'sky_wyvern':ROOT/'assets/3d pipeline/enemy/sky_wyvern/raw/sky_wyvern_body_concept_v001.png',
 'minotaur':ROOT/'assets/3d pipeline/enemy/minotaur/raw/minotaur_body_concept_v001.png',
 'ogre':ROOT/'assets/using/enemies/normal/ogre.png',
 'hellhound':ROOT/'assets/using/enemies/normal/hellhound.png',
 'orc':ROOT/'assets/3d pipeline/enemy/orc/raw/orc_normal_concept_v001.jpg',
 'troll':ROOT/'assets/using/enemies/normal/all element mobs/Troll/troll_normal.png',
}
name=sys.argv[1];mode=sys.argv[2]
out=ROOT/'assets/3d pipeline/enemy'/name/'raw'
out.mkdir(parents=True,exist_ok=True);(out/'.gdignore').touch()
record=out/'conversion_task_v001.json'
key=(ROOT/'tools/model3d/meshy_key.py').read_text().strip().strip(chr(34))
if mode=='submit':
    assert not record.exists(), 'Resume existing task rather than spending twice.'
    texture='--untextured' not in sys.argv
    task=api.image_to_3d(key,str(REFERENCES[name]),polycount=10000,texture=texture)
    record.write_text(json.dumps({'family':name,'reference':str(REFERENCES[name]),'body_task':task,'body_credits':15 if texture else 5},indent=2))
    print(name,'submitted:',task)
elif mode=='status':
    task=json.loads(record.read_text())
    result=api._req(key,'GET','image-to-3d/'+task['body_task'])
    print(name,result.get('status'),result.get('progress'))
    if result.get('status')=='SUCCEEDED':
        path=out/(name+'_body_v001.glb')
        if not path.exists():api.download(result,str(out),name+'_body_v001')
        task['body_file']=str(path);record.write_text(json.dumps(task,indent=2))
elif mode=='rig':
    task=json.loads(record.read_text());assert 'rig_task' not in task, 'Resume, never duplicate rig spend.'
    task['rig_task']=api.rig(key,task['body_task'],height=1.7)
    task['rig_credits']=5;record.write_text(json.dumps(task,indent=2));print(name,'rig submitted:',task['rig_task'])
elif mode=='rig-status':
    task=json.loads(record.read_text());result=api._req(key,'GET','rigging/'+task['rig_task'])
    print(name,'rig',result.get('status'),result.get('progress'))
    if result.get('status')=='SUCCEEDED':
        if not (out/(name+'_rigged_v001.glb')).exists():api.download_rig_bundle(result,str(out),name+'_rigged_v001')
else:raise ValueError(mode)
