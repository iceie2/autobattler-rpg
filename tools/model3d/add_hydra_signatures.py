"""Append six individually authored Hydra signatures; never overwrite v001.

Uses the existing glTF skeleton and textures verbatim. Bone rotations are
authored about model-space axes and converted through each parent's rest
orientation, rather than assuming the creature's neck bones share a roll.
Run with the bundled Python. No external generation service is used.
"""
import json, math, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KINDS = ['normal', 'fire', 'water', 'earth', 'air', 'lightning']
NAMES = ['crushing_jaws', 'scorched_ground', 'undertow', 'stonefangs', 'gale_sweep', 'forked_discharge']

def mul(a, b):
    x,y,z,w=a; X,Y,Z,W=b
    return [w*X+x*W+y*Z-z*Y, w*Y-x*Z+y*W+z*X, w*Z+x*Y-y*X+z*W, w*W-x*X-y*Y-z*Z]

def inv(q): return [-q[0],-q[1],-q[2],q[3]]
def axis(v, a): return [*(x*math.sin(a/2) for x in v), math.cos(a/2)]

def angles(kind, name, t):
    # 1.4s clip; contact is at 0.9s, with an explicit anticipatory pose.
    wind = math.sin(min(t/.9, 1)*math.pi/2)
    release = max(0, 1-(t-.9)/.5) if t >= .9 else 0
    prep = wind if t < .9 else release
    snap = math.sin(max(0, min(1, (t-.75)/.3))*math.pi)
    side = -1 if 'NeckL' in name else (1 if 'NeckR' in name else 0)
    seg = int(name[-1]) if name.startswith('Neck') else 1
    if name == 'Hips':
        return ([.035*prep, 0, 0] if kind in ('fire','water') else
                [-.045*prep, 0, .025*math.sin(t*7)*prep] if kind == 'earth' else [0,0,0])
    if name.startswith('Tail'): return [0, .12*math.sin(t*6)*prep, 0]
    if kind == 'normal': return [-.13*prep+.32*snap, -side*.22*prep, side*.04*prep]
    if kind == 'fire': return [-.20*prep+.38*snap, side*.08*prep, 0]
    if kind == 'water': return [.12*prep-.25*snap, -side*.14*prep, side*.06*math.sin(t*8)*prep]
    if kind == 'earth': return [.20*prep-.40*snap, side*.10*prep, 0]
    if kind == 'air': return [-.06*prep, .32*math.sin(t*4.5+side*.25)*prep, side*.10*prep]
    return [-.22*prep+.09*math.sin(t*24+side*2)*prep, side*.13*prep, .06*math.sin(t*18+seg)*prep]

def build(kind, clip):
    folder = ROOT / 'assets' / '3d pipeline' / 'enemy' / f'hydra_{kind}'
    source = folder / f'hydra_{kind}_v001.glb'
    output = folder / f'hydra_{kind}_v002.glb'
    raw = source.read_bytes(); size, _ = struct.unpack_from('<II', raw, 12)
    doc = json.loads(raw[20:20+size]); offset=20+size
    bsize, _ = struct.unpack_from('<II', raw, offset)
    binary=bytearray(raw[offset+8:offset+8+bsize])
    parent={c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
    def world(i):
        q=doc['nodes'][i].get('rotation',[0,0,0,1])
        return mul(world(parent[i]),q) if i in parent else q
    def accessor(values, width):
        while len(binary)%4: binary.append(0)
        start=len(binary)
        binary.extend(struct.pack('<'+'f'*len(values),*values))
        view=len(doc['bufferViews']); doc['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':len(values)*4})
        idx=len(doc['accessors']); entry={'bufferView':view,'componentType':5126,'count':len(values)//width,'type':'SCALAR' if width==1 else 'VEC4'}
        if width==1: entry.update(min=[min(values)],max=[max(values)])
        doc['accessors'].append(entry); return idx
    times=[i/30 for i in range(43)]; ti=accessor(times,1)
    anim={'name':clip,'samplers':[],'channels':[]}
    for i,node in enumerate(doc['nodes']):
        name=node.get('name','')
        if name != 'Hips' and not (name.startswith(('Neck','Tail')) and not name.endswith('_end')): continue
        rest=node.get('rotation',[0,0,0,1]); pq=world(parent[i]) if i in parent else [0,0,0,1]
        values=[]; last=None
        for t in times:
            rx,ry,rz=angles(kind,name,t)
            delta=mul(mul(axis([1,0,0],rx),axis([0,1,0],ry)),axis([0,0,1],rz))
            q=mul(mul(mul(inv(pq),delta),pq),rest)
            if last and sum(a*b for a,b in zip(last,q))<0: q=[-x for x in q]
            values.extend(q); last=q
        oi=accessor(values,4); sampler=len(anim['samplers'])
        anim['samplers'].append({'input':ti,'output':oi,'interpolation':'LINEAR'})
        anim['channels'].append({'sampler':sampler,'target':{'node':i,'path':'rotation'}})
    doc['animations'].append(anim); doc['buffers'][0]['byteLength']=len(binary)
    js=json.dumps(doc,separators=(',',':')).encode()
    js+=b' '*((-len(js))%4); binary+=b'\0'*((-len(binary))%4)
    out=struct.pack('<III',0x46546c67,2,12+8+len(js)+8+len(binary))+struct.pack('<II',len(js),0x4e4f534a)+js+struct.pack('<II',len(binary),0x004e4942)+binary
    output.write_bytes(out)
    print(kind, clip, len(anim['channels']), 'bone tracks ->', output.name)

if __name__=='__main__':
    for kind, clip in zip(KINDS,NAMES): build(kind,clip)
