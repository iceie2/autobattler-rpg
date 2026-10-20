"""Riveted clockwork robot, winding key and rigid piston limbs from its sprite."""
import sys, pathlib, math
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from local_enemy_lib import Asset
bones=[('Hips',(0,0,.6),(0,0,.8),None),('Chest',(0,0,.85),(0,0,1.05),'Hips'),('Head',(0,0,1.25),(0,0,1.57),'Chest'),('Key',(0,.27,1.18),(0,.4,1.18),'Chest')]
for side,x in [('L',.36),('R',-.36)]:
    bones.extend([('Arm'+side,(x,0,1.06),(x*1.6,0,.75),'Chest'),('Hand'+side,(x*1.6,0,.75),(x*1.8,-.1,.54),'Arm'+side),('Leg'+side,(x*.6,0,.50),(x*.6,0,.2),'Hips'),('Foot'+side,(x*.6,0,.2),(x*.6,-.1,.08),'Leg'+side)])
bones.extend([('BoundsBase',(0,0,0),(0,0,.01),'Hips'),('BoundsTop',(0,0,1.75),(0,0,1.76),'Hips')])
a=Asset('windup_bot',bones)
shell=a.mat('Bot_Shell',(.48,.58,.61),.48,.25);dark=a.mat('Bot_Seams',(.09,.15,.16));brass=a.mat('Bot_Brass',(.70,.40,.09),.4,.4)
key=a.mat('Bot_Key',(.70,.15,.13));white=a.mat('Bot_KeyStripe',(.82,.81,.68));eye=a.mat('Bot_Eye',(.98,.58,.1),.3)
a.ball('Belly',(0,0,.79),(.39,.27,.40),'Chest',shell);a.ball('Head',(0,-.01,1.34),(.29,.255,.32),'Head',shell)
a.torus('BellySeam',(0,-.255,.79),.255,.014,'Chest',dark)
for z in [.60,.73,.86,.99]:a.ball('Rivet',(0,-.269,z),(.018,.011,.018),'Chest',brass)
for x in [-.14,.14]:
    a.torus('EyeRing',(x,-.24,1.4),.07,.017,'Head',brass)
    a.ball('Eye',(x,-.257,1.4),(.048,.026,.048),'Head',eye)
a.ball('MouthDark',(0,-.258,1.20),(.14,.025,.08),'Head',dark)
for x in [-.10,-.06,-.02,.02,.06,.10]:a.tube('MouthGrille',(x,-.286,1.15),(x,-.286,1.25),.008,.008,'Head',shell)
for s,x in [('L',.36),('R',-.36)]:
    a.ball('Shoulder',(x,0,1.06),(.12,)*3,'Arm'+s,shell)
    a.tube('ArmPiston',(x,0,1.06),(x*1.6,0,.75),.048,.048,'Arm'+s,dark)
    for k in [.25,.5,.75]:
        a.ball('ArmCollar',(x*(1+.6*k),0,1.06-.31*k),(.069,.055,.057),'Arm'+s,shell)
    a.ball('Mitten',(x*1.75,-.03,.56),(.13,.11,.18),'Hand'+s,shell)
    a.ball('Thumb',(x*1.43,-.13,.59),(.063,.07,.1),'Hand'+s,shell)
    a.tube('LegPiston',(x*.6,0,.50),(x*.6,0,.15),.046,.046,'Leg'+s,dark)
    a.ball('Knee',(x*.6,0,.29),(.065,)*3,'Leg'+s,brass)
    a.box('Boot',(x*.6,-.055,.095),(.25,.32,.16),'Foot'+s,shell)
a.tube('KeyShaft',(0,.21,1.18),(0,.48,1.18),.038,.038,'Key',brass)
for x in [-.17,.17]:
    a.torus('WindKeyLoop',(x,.49,1.35),.11,.035,'Key',key)
    a.box('KeyStripe',(x,.454,1.35),(.034,.018,.20),'Key',white,.004)
a.box('KeyBridge',(0,.49,1.27),(.35,.055,.07),'Key',key)
a.join()
def idle(t):return {'Chest':math.sin(t*math.tau)*1.2,'Key':{'axis':(0,1,0),'angle':math.sin(t*math.tau)*6}}
def walk(t):
    p=idle(t)
    for s,phase in [('L',0),('R',math.pi)]:
        p['Leg'+s]=math.sin(t*math.tau+phase)*25;p['Foot'+s]=-p['Leg'+s]*.6;p['Arm'+s]=-p['Leg'+s]*.4
    return p
a.action('idle',60,idle);a.action('walk',30,walk)
a.action('attack',12,lambda t:{'ArmR':-55*math.sin(t*math.pi),'HandR':-20*math.sin(t*math.pi)})
a.action('skill',30,lambda t:{'ArmR':-80*math.sin(t*math.pi),'HandR':{'offset':(0,-.18*math.sin(t*math.pi),0)},'Chest':8*math.sin(t*math.pi),'Key':{'axis':(0,1,0),'angle':360*t}})
a.action('hurt',12,lambda t:{'Chest':-10*math.sin(t*math.pi),'Head':12*math.sin(t*math.pi)})
a.action('death',30,lambda t:{'Hips':{'axis':(0,1,0),'angle':85*min(t*1.5,1),'offset':(0,0,-.4*min(t*1.5,1))},'ArmL':40*min(t*1.5,1),'Head':25*min(t*1.5,1)})
a.export()
