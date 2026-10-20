"""Standalone Rat and Skeleton families, matched to their active sprites."""
import sys,pathlib,math
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from local_enemy_lib import Asset
name=sys.argv[-1];assert name in ('rat','skeleton')
rat=name=='rat';headz=1.10 if rat else 1.44
bones=[('Hips',(0,0,.47),(0,0,.67),None),('Chest',(0,0,.72),(0,0,.94),'Hips'),('Head',(0,0,headz),(0,0,headz+.25),'Chest'),('Jaw',(0,-.15,headz-.13),(0,-.26,headz-.13),'Head')]
for s,x in [('L',.25),('R',-.25)]:
    bones.extend([('Arm'+s,(x,0,.87),(x*1.5,0,.65),'Chest'),('Hand'+s,(x*1.5,0,.65),(x*1.5,-.1,.48),'Arm'+s),('Leg'+s,(x*.7,0,.42),(x*.7,0,.23),'Hips'),('Foot'+s,(x*.7,0,.23),(x*.7,-.12,.06),'Leg'+s)])
if not rat:bones.append(('weapon_r',(-.375,-.12,.55),(-.375,-.12,1.0),'HandR'))
bones.extend([('BoundsBase',(0,0,0),(0,0,.01),'Hips'),('BoundsTop',(0,0,headz+.37),(0,0,headz+.38),'Hips')])
a=Asset(name,bones,version=2)
if rat:
    fur=a.mat('Rat_Fur',(.32,.27,.22));belly=a.mat('Rat_Belly',(.52,.45,.37));pink=a.mat('Rat_Skin',(.66,.33,.27));black=a.mat('Rat_Pupil',(.025,.016,.01));red=a.mat('Rat_Eye',(.70,.018,.012));tooth=a.mat('Rat_Teeth',(.82,.75,.42))
    a.ball('Body',(0,0,.57),(.28,.22,.37),'Hips',fur);a.ball('Belly',(0,-.17,.60),(.21,.08,.28),'Hips',belly)
    a.ball('Head',(0,-.01,1.05),(.29,.24,.28),'Head',fur)
    for sign in [-1,1]:
        a.ball('Ear',(sign*.245,0,1.26),(.14,.065,.17),'Head',fur);a.ball('InnerEar',(sign*.245,-.055,1.27),(.105,.025,.13),'Head',pink)
        a.ball('EyeSocket',(sign*.14,-.217,1.12),(.082,.042,.075),'Head',black);a.ball('RedEye',(sign*.14,-.25,1.12),(.044,.02,.048),'Head',red)
        a.ball('Cheek',(sign*.09,-.235,.99),(.14,.11,.085),'Head',belly)
        a.tube('AngryBrow',(sign*.22,-.22,1.20),(sign*.06,-.26,1.15),.036,.027,'Head',fur)
        a.box('Incisor',(sign*.033,-.28,.91),(.048,.043,.13),'Jaw',tooth,.008)
        for j in range(3):a.tube('Whisker',(sign*.18,-.28,.99),(sign*.42,-.30,.96+j*.045),.004,.001,'Head',black,8)
    a.ball('Nose',(0,-.337,1.01),(.074,.051,.04),'Head',pink)
    for s,x in [('L',.25),('R',-.25)]:
        a.ball('UpperArm',(x,0,.78),(.115,.115,.18),'Arm'+s,fur);a.ball('Hand',(x*1.5,-.09,.57),(.075,.065,.08),'Hand'+s,pink)
        a.tube('Forearm',(x*1.25,0,.68),(x*1.5,-.09,.57),.054,.046,'Hand'+s,fur)
        a.ball('Haunch',(x*.7,0,.32),(.13,.14,.22),'Leg'+s,fur);a.ball('Foot',(x*.7,-.09,.07),(.095,.17,.047),'Foot'+s,pink)
        for toe in [-1,0,1]:a.tube('Finger',(x*1.5+toe*.031,-.12,.56),(x*1.5+toe*.034,-.18,.49),.011,.003,'Hand'+s,pink)
else:
    ivory=a.mat('Skeleton_Bone',(.73,.65,.45));black=a.mat('Skeleton_Sockets',(.022,.018,.013));cloth=a.mat('Skeleton_Cloth',(.22,.20,.15));steel=a.mat('Skeleton_Sword',(.32,.25,.17),.6,.25)
    a.ball('Skull',(0,0,1.42),(.21,.17,.25),'Head',ivory)
    a.tube('Neck',(0,0,.98),(0,0,1.24),.028,.028,'Head',ivory)
    a.tube('Spine',(0,.025,.52),(0,.025,.98),.021,.021,'Chest',ivory)
    for sign in [-1,1]:a.ball('EyeSocket',(sign*.087,-.147,1.46),(.068,.038,.071),'Head',black)
    a.ball('NoseHole',(0,-.164,1.37),(.032,.02,.039),'Head',black)
    a.ball('Jaw',(0,-.06,1.23),(.15,.13,.07),'Jaw',ivory)
    for i in range(7):
        x=(i-3)*.035;a.box('UpperTooth',(x,-.151,1.29),(.026,.037,.040),'Head',ivory,.004);a.box('LowerTooth',(x,-.163,1.245),(.026,.034,.024),'Jaw',ivory,.004)
    for z in [.56,.65,.74,.83,.92]:
        a.ball('Vertebra',(0,.025,z),(.055,.05,.033),'Chest',ivory)
    for z,r in [(.77,.15),(.86,.18),(.95,.20)]:a.torus('Rib',(0,0,z),r,.022,'Chest',ivory,rotation=(0,0,0))
    a.tube('Sternum',(0,-.18,.77),(0,-.18,1.0),.022,.025,'Chest',ivory)
    for sign in [-1,1]:a.tube('CollarBone',(0,0,1.0),(sign*.25,0,.91),.022,.028,'Chest',ivory)
    a.torus('Pelvis',(0,0,.47),.16,.04,'Hips',ivory,rotation=(0,0,0))
    a.tube('RaggedSkirt',(0,0,.36),(0,0,.54),.21,.16,'Hips',cloth,8)
    for s,x in [('L',.25),('R',-.25)]:
        for n,p,q in [('Arm'+s,(x,0,.87),(x*1.5,0,.65)),('Hand'+s,(x*1.5,0,.65),(x*1.5,-.1,.48)),('Leg'+s,(x*.7,0,.42),(x*.7,0,.23)),('Foot'+s,(x*.7,0,.23),(x*.7,-.12,.06))]:
            a.tube('LongBone',p,q,.027,.024,n,ivory)
            a.ball('BoneJoint',p,(.043,)*3,n,ivory)
        a.box('Palm',(x*1.5,-.09,.48),(.065,.055,.07),'Hand'+s,ivory,.012)
        for toe in [-1,0,1]:a.tube('Finger',(x*1.5+toe*.026,-.10,.47),(x*1.5+toe*.029,-.13,.40),.008,.005,'Hand'+s,ivory)
    a.tube('SwordGrip',(-.375,-.13,.40),(-.375,-.13,.64),.025,.025,'weapon_r',cloth)
    a.box('SwordGuard',(-.375,-.13,.65),(.22,.055,.05),'weapon_r',steel,.006)
    a.box('SwordBlade',(-.375,-.13,.96),(.075,.035,.58),'weapon_r',steel,.005)
    a.tube('SwordTip',(-.375,-.13,1.24),(-.375,-.13,1.38),.052,0,'weapon_r',steel,4)
a.join()
def idle(t):return {'Chest':math.sin(t*math.tau)*1.5,'Head':-math.sin(t*math.tau)}
def walk(t):
    p=idle(t)
    for s,phase in [('L',0),('R',math.pi)]:p['Leg'+s]=math.sin(t*math.tau+phase)*20;p['Foot'+s]=-p['Leg'+s]*.5;p['Arm'+s]=-p['Leg'+s]*.6
    return p
a.action('idle',60,idle);a.action('walk',24,walk)
a.action('attack',15,lambda t:{'Head':-18*math.sin(t*math.pi),'Jaw':25*math.sin(t*math.pi),'ArmR':-60*math.sin(t*math.pi) if not rat else -12*math.sin(t*math.pi)})
a.action('skill',24,lambda t:{'Chest':-8*math.sin(t*math.pi),'ArmL':-55*math.sin(t*math.pi),'ArmR':-55*math.sin(t*math.pi),'Jaw':25*math.sin(t*math.pi)})
a.action('hurt',12,lambda t:{'Chest':-12*math.sin(t*math.pi),'Head':14*math.sin(t*math.pi)})
a.action('death',30,lambda t:{'Hips':{'axis':(0,1,0),'angle':80*min(t*1.5,1),'offset':(0,0,-.25*min(t*1.5,1))},'Head':25*min(t*1.5,1)})
a.export()
