"""Separate firebird/crow family assets with layered feathers, wing and fan-tail rigs."""
import sys,pathlib,math,bpy
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from local_enemy_lib import Asset
name=sys.argv[-1];assert name in ('ember_phoenix','storm_crow');fire=name=='ember_phoenix'
bones=[('Hips',(0,0,.64),(0,0,.88),None),('Chest',(0,-.05,.89),(0,-.1,1.02),'Hips'),('Head',(0,-.15,1.12),(0,-.20,1.32),'Chest'),('Tail',(0,.12,.67),(0,.56,.30),'Hips')]
for s,sign in [('L',1),('R',-1)]:
    bones.extend([('Wing'+s,(sign*.16,0,.95),(sign*.47,0,1.06),'Chest'),('WingTip'+s,(sign*.47,0,1.06),(sign*.95,0,1.16),'Wing'+s),('Leg'+s,(sign*.10,-.01,.68),(sign*.12,-.1,.39),'Hips')])
bones.extend([('BoundsBase',(0,0,0),(0,0,.01),'Hips'),('BoundsTop',(0,0,1.40),(0,0,1.41),'Hips')])
a=Asset(name,bones)
body=a.mat('Bird_Body',(.39,.045,.012) if fire else (.027,.04,.085))
feather=a.mat('Bird_Feathers',(.80,.16,.016) if fire else (.065,.10,.19))
tip=a.mat('Bird_Tips',(.22,.15,.11) if fire else (.24,.49,.66))
gold=a.mat('Bird_Beak',(.93,.46,.025) if fire else (.09,.15,.20))
glow=a.mat('Bird_Glow',(1,.46,.025) if fire else (.27,.83,1),.45)
p=glow.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(1,.46,.025,1) if fire else (.27,.83,1,1);p.inputs['Emission Strength'].default_value=.8
black=a.mat('Bird_Sockets',(.012,.006,.003))
a.ball('Body',(0,0,.82),(.18,.23,.28),'Hips',body)
a.ball('Chest',(0,-.10,.94),(.19,.19,.22),'Chest',feather)
a.ball('Head',(0,-.19,1.18),(.16,.17,.17),'Head',body)
a.tube('Beak',(0,-.31,1.17),(0,-.51,1.11),.075,.008,'Head',gold,6)
for sign in [-1,1]:
    a.ball('EyeSocket',(sign*.118,-.30,1.22),(.043,.025,.032),'Head',black)
    a.ball('Eye',(sign*.128,-.317,1.22),(.026,.014,.022),'Head',glow)
for j in range(4):
    a.tube('Crest',(0,-.18+j*.042,1.28),(0,-.04+j*.06,1.39-(j%2)*.035),.058,.005,'Head',glow if fire else tip,6)
def plume(n,start,end,width,bone,material):
    # Flattened tapered feather, with a convex rib; more readable than spheres.
    from mathutils import Vector
    start,end=Vector(start),Vector(end);d=(end-start).normalized();side=d.cross(Vector((0,1,0))).normalized()*width
    mid=start.lerp(end,.44);verts=[tuple(start),tuple(mid+side),tuple(end),tuple(mid-side),tuple(mid+Vector((0,-.028,0)))]
    faces=[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2,1)]
    mesh=bpy.data.meshes.new(n);mesh.from_pydata(verts,[],faces);mesh.update();ob=bpy.data.objects.new(n,mesh);bpy.context.collection.objects.link(ob);bpy.context.view_layer.objects.active=ob;ob.select_set(True);a.bind(ob,n,bone,material,False)
for s,sign in [('L',1),('R',-1)]:
    a.ball('WingShoulder',(sign*.22,0,.97),(.15,.09,.12),'Wing'+s,body)
    a.tube('WingSpar',(sign*.16,0,.95),(sign*.48,0,1.06),.07,.04,'Wing'+s,body,8)
    for j in range(7):
        start=(sign*(.30+j*.055),0,1.0+j*.028)
        end=(sign*(.70+j*.055),.035, .77+j*.083)
        plume('FlightFeather',start,end,.065,'Wing'+s if j<3 else 'WingTip'+s,tip if j>4 else feather)
        if fire:plume('EmberFeather',start,(end[0]*.86,-.015,end[2]+.02),.031,'Wing'+s if j<3 else 'WingTip'+s,glow)
    for j in range(4):plume('WingCover', (sign*.22,-.045,1.01),(sign*(.45+j*.075),-.045,.97+j*.046),.045,'Wing'+s,feather)
    a.tube('Leg',(sign*.1,-.01,.68),(sign*.12,-.1,.39),.025,.018,'Leg'+s,gold,8)
    for j in [-1,0,1]:a.tube('Talon',(sign*.12,-.1,.4),(sign*.12+j*.037,-.21,.34),.015,.004,'Leg'+s,tip,6)
for j in range(5):
    plume('FanTail',(0,.13,.68),((j-2)*.105,.57,.30+abs(j-2)*.035),.057,'Tail',feather if j%2==0 else tip)
    if fire:plume('TailEmber',(0,.15,.68),((j-2)*.09,.51,.36+abs(j-2)*.035),.022,'Tail',glow)
a.join()
def flap(t):return {'WingL':{'axis':(0,1,0),'angle':22*math.sin(t*math.tau)},'WingR':{'axis':(0,1,0),'angle':-22*math.sin(t*math.tau)},'WingTipL':{'axis':(0,1,0),'angle':14*math.sin(t*math.tau-.5)},'WingTipR':{'axis':(0,1,0),'angle':-14*math.sin(t*math.tau-.5)},'Tail':4*math.sin(t*math.tau),'Chest':2*math.sin(t*math.tau)}
a.action('idle',36,flap);a.action('walk',24,flap);a.action('fly',24,flap)
def strike(t):
    p=flap(t);p.update({'Head':-18*math.sin(t*math.pi),'Chest':15*math.sin(t*math.pi),'LegL':-30*math.sin(t*math.pi),'LegR':-30*math.sin(t*math.pi)});return p
a.action('attack',18,strike);a.action('skill',24,strike)
a.action('hurt',12,lambda t:{'Head':12*math.sin(t*math.pi),'Chest':-12*math.sin(t*math.pi)})
a.action('death',30,lambda t:{'Hips':{'axis':(0,1,0),'angle':75*min(t*1.5,1),'offset':(0,0,-.3*min(t*1.5,1))},'WingL':{'axis':(0,1,0),'angle':55*min(t*1.5,1)},'WingR':{'axis':(0,1,0),'angle':-55*min(t*1.5,1)}})
a.export()
