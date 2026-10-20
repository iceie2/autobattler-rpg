"""Locally authored stone, crystal, root and coral silhouettes from the active sprites."""
import sys,pathlib,math,bpy
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parent))
from local_enemy_lib import Asset
name=sys.argv[-1];assert name in ('stone_golem','crystal_crab','root_walker','coral_husk')
crab=name=='crystal_crab';tree=name=='root_walker';coral=name=='coral_husk'
bones=[('Hips',(0,0,.45 if crab else .7),(0,0,.65 if crab else .95),None),('Chest',(0,0,.95),(0,0,1.2),'Hips'),('Head',(0,0,1.35),(0,0,1.7),'Chest')]
if crab: bones=[('Hips',(0,0,.42),(0,0,.46),None),('Chest',(0,-.1,.44),(0,-.1,.50),'Hips'),('Head',(0,-.2,.46),(0,-.2,.52),'Chest')]
if crab:
    for s,sign in [('L',1),('R',-1)]:
        for j in range(3):
            y=-.22+j*.22;n='Leg'+s+str(j)
            bones.extend([(n,(sign*.26,y,.38),(sign*.55,y,.22),'Hips'),(n+'Foot',(sign*.55,y,.22),(sign*.68,y-.1,.04),n)])
        bones.extend([('Arm'+s,(sign*.25,-.30,.40),(sign*.55,-.55,.51),'Hips'),('Hand'+s,(sign*.55,-.55,.51),(sign*.62,-.75,.62),'Arm'+s),('Pincer'+s,(sign*.55,-.55,.51),(sign*.77,-.7,.61),'Hand'+s)])
elif tree:
    for s,sign in [('L',1),('R',-1)]:
        for j,y in enumerate([-.18,.2]):
            n='Leg'+s+str(j);bones.extend([(n,(sign*.15,y,.68),(sign*.42,y,.34),'Hips'),(n+'Foot',(sign*.42,y,.34),(sign*.56,y-.18,.035),n)])
        bones.extend([('Arm'+s,(sign*.26,0,1.22),(sign*.49,0,.98),'Chest'),('Hand'+s,(sign*.49,0,.98),(sign*.65,-.1,1.12),'Arm'+s)])
else:
    for s,x in [('L',.36),('R',-.36)]:
        bones.extend([('Arm'+s,(x,0,1.25),(x*1.36,0,.96),'Chest'),('Hand'+s,(x*1.36,0,.96),(x*1.46,-.03,.69),'Arm'+s),('Leg'+s,(x*.58,0,.68),(x*.7,0,.36),'Hips'),('Foot'+s,(x*.7,0,.36),(x*.7,-.1,.09),'Leg'+s)])
top=.98 if crab else 1.85
bones.extend([('BoundsBase',(0,0,0),(0,0,.01),'Hips'),('BoundsTop',(0,0,top),(0,0,top+.01),'Hips')])
a=Asset(name,bones,version=2)
def glow(n,c):
    m=a.mat(n,c,.55);p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(*c,1);p.inputs['Emission Strength'].default_value=.65;return m
def rock(n,c,s,b,m):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=1,radius=1,location=c);ob=bpy.context.object;ob.scale=s;ob.rotation_euler=(.1,.13,.17);a.bind(ob,n,b,m,False)
if crab:
    purple=a.mat('Crab_Shell',(.30,.09,.56));light=a.mat('Crab_Facet',(.58,.26,.86),.42);dark=a.mat('Crab_Joints',(.14,.04,.23));red=glow('Crab_Eyes',(.86,.03,.02))
    rock('Carapace',(0,0,.42),(.42,.36,.27),'Hips',purple)
    for x,y,z,r in [(-.24,.05,.57,.11),(.24,.05,.57,.11),(0,.20,.6,.14),(0,0,.61,.15),(-.12,-.13,.58,.09),(.12,-.13,.58,.09)]:
        a.tube('Crystal',(x,y,z),(x*.9,y,z+r*2.3),r,.002,'Hips',light,5)
    for sign in [-1,1]:
        a.tube('EyeStalk',(sign*.13,-.26,.4),(sign*.15,-.38,.55),.025,.025,'Hips',dark)
        a.ball('RedEye',(sign*.15,-.39,.55),(.037,.032,.048),'Hips',red)
    for s,sign in [('L',1),('R',-1)]:
        for j in range(3):
            y=-.22+j*.22;n='Leg'+s+str(j)
            a.tube('LegSegment',(sign*.26,y,.38),(sign*.55,y,.22),.056,.045,n,purple,6)
            a.tube('LegTip',(sign*.55,y,.22),(sign*.68,y-.1,.04),.045,.009,n+'Foot',light,6)
        a.tube('ClawArm',(sign*.25,-.30,.40),(sign*.55,-.55,.51),.075,.06,'Arm'+s,purple,6)
        rock('ClawPalm',(sign*.57,-.56,.53),(.14,.13,.15),'Hand'+s,purple)
        a.tube('FixedPincer',(sign*.51,-.58,.57),(sign*.50,-.83,.72),.09,.009,'Hand'+s,light,5)
        a.tube('MovingPincer',(sign*.68,-.57,.57),(sign*.62,-.80,.73),.09,.009,'Pincer'+s,light,5)
elif tree:
    wood=a.mat('Root_Bark',(.25,.17,.09));light=a.mat('Root_Ridges',(.40,.29,.15));moss=a.mat('Root_Moss',(.19,.38,.07));black=a.mat('Root_Sockets',(.035,.032,.017));green=glow('Root_Eyes',(.21,.83,.21))
    a.tube('Trunk',(0,0,.62),(0,0,1.48),.28,.22,'Chest',wood,10)
    for sign in [-1,1]:
        a.ball('EyeSocket',(sign*.115,-.197,1.38),(.083,.049,.095),'Head',black)
        a.ball('Eye',(sign*.115,-.238,1.38),(.048,.020,.049),'Head',green)
    a.ball('Mouth',(0,-.249,1.16),(.10,.015,.032),'Chest',black)
    for i in range(8):
        ang=i*math.tau/8;x=.24*math.cos(ang);y=.24*math.sin(ang)
        a.tube('BarkRidge',(x,y,.7),(x*.9,y*.9,1.47),.036,.025,'Chest',light,5)
    for i in range(5):
        x=(i-2)*.09;a.tube('CrownBranch',(x,0,1.44),(x*1.6,.04,1.63+(.17 if i%2==0 else .05)),.05,.016,'Head',wood,7)
    for s,sign in [('L',1),('R',-1)]:
        for j,y in enumerate([-.18,.2]):
            n='Leg'+s+str(j);a.tube('RootUpper',(sign*.15,y,.68),(sign*.42,y,.34),.08,.055,n,wood,6)
            a.tube('RootLower',(sign*.42,y,.34),(sign*.56,y-.18,.035),.055,.015,n+'Foot',light,6)
            for toe in [-1,0,1]:a.tube('RootToe',(sign*.56,y-.18,.04),(sign*(.59+toe*.045),y-.3,.018),.022,.003,n+'Foot',wood,5)
        a.tube('BranchArm',(sign*.26,0,1.22),(sign*.49,0,.98),.066,.044,'Arm'+s,wood,6)
        a.tube('BranchForearm',(sign*.49,0,.98),(sign*.65,-.1,1.12),.045,.033,'Hand'+s,wood,6)
        for j in range(3):a.tube('BranchFinger',(sign*.65,-.1,1.12),(sign*(.69+j*.04),-.20,1.1+j*.045),.023,.004,'Hand'+s,light,5)
        a.ball('MossShoulder',(sign*.26,0,1.28),(.19,.14,.08),'Chest',moss)
        for j in range(3):a.tube('HangingVine',(sign*(.20+j*.04),-.06,1.26),(sign*(.20+j*.04),-.06,1.04-j*.035),.009,.004,'Chest',moss,5)
else:
    stone=a.mat('Husk_Shell' if coral else 'Golem_Stone',(.12,.29,.32) if coral else (.36,.22,.13))
    pale=a.mat('Husk_Ribs' if coral else 'Golem_Facet',(.29,.46,.44) if coral else (.52,.35,.23))
    dark=a.mat('Body_Seams',(.04,.08,.08) if coral else (.07,.05,.035));green=glow('Body_Glow',(.24,.9,.48));moss=a.mat('Moss',(.21,.39,.12))
    if coral:
        a.ball('Spine',(0,.1,1.0),(.06,.05,.29),'Chest',pale)
        for z,r in [(.90,.18),(1.01,.22),(1.12,.24)]:a.torus('ExposedRib',(0,0,z),r,.022,'Chest',pale,rotation=(0,0,0))
        for sign in [-1,1]:rock('ChestShell',(sign*.14,-.04,1.22),(.16,.17,.09),'Chest',stone)
    else:
        rock('Torso',(0,0,1.12),(.39,.23,.31),'Chest',stone)
        rock('Belly',(0,0,.86),(.28,.21,.14),'Hips',pale)
    rock('Pelvis',(0,0,.67),(.28,.20,.15),'Hips',stone)
    rock('Head',(0,0,1.56),(.22,.18,.23),'Head',stone)
    for sign in [-1,1]:
        a.ball('Eye',(sign*.085,-.168,1.59),(.037,.018,.019),'Head',green)
        a.tube('Brow',(sign*.02,-.165,1.63),(sign*.16,-.15,1.66),.036,.025,'Head',pale)
    a.box('Mouth',(0,-.176,1.48),(.15,.016,.028),'Head',dark,.002)
    rock('Core',(0,-.234,1.15),(.066,.028,.09),'Chest',green)
    for s,x in [('L',.36),('R',-.36)]:
        for n,c,scale in [('Arm'+s,(x,0,1.24),(.18,.17,.18)),('Arm'+s,(x*1.2,0,1.08),(.11,.12,.15)),('Hand'+s,(x*1.36,0,.87),(.13,.14,.16)),('Hand'+s,(x*1.46,-.02,.69),(.12,.12,.13)),('Leg'+s,(x*.58,0,.53),(.12,.14,.18)),('Foot'+s,(x*.7,0,.25),(.12,.13,.14)),('Foot'+s,(x*.7,-.08,.09),(.15,.21,.08))]:rock('RockSegment',c,scale,n,stone)
        if coral:
            for j in range(3):a.tube('Finger',(x*1.46+j*.035-.035,-.07,.64),(x*1.46+j*.038-.038,-.1,.55),.025,.008,'Hand'+s,pale,6)
        else:
            a.ball('MossPatch',(x,0,1.38),(.16,.12,.037),'Arm'+s,moss)
            for j in range(3):a.ball('MossSpot',(x*.7,-.09,.4+j*.1),(.05,.015,.023),'Leg'+s,moss)
    if coral:
        orange=a.mat('Coral_Orange',(.75,.27,.055));purple=a.mat('Coral_Purple',(.33,.09,.43))
        for x,z,bone in [(-.29,1.36,'Chest'),(.29,1.36,'Chest'),(-.48,.87,'HandR'),(.48,.87,'HandL'),(.08,1.74,'Head')]:
            for j in range(3):
                end=(x+(j-1)*.06,.045,z+.15+.06*(j%2));a.tube('CoralBranch',(x,.06,z),end,.026,.015,bone,orange,6)
                a.tube('CoralTwig',end,(end[0]+.045,.03,end[2]+.05),.014,.006,bone,purple,6)
    else:
        for x,y in [(-.18,.05),(.13,.03),(.3,0)]:
            a.tube('FlowerStem',(x,y,1.38),(x,y,1.50),.009,.007,'Chest',moss,5)
            for j in range(5):a.ball('FlowerPetal',(x+.026*math.cos(j*math.tau/5),y+.026*math.sin(j*math.tau/5),1.50),(.022,.016,.012),'Chest',green)
a.join()
def idle(t):return {'Chest':math.sin(t*math.tau)*1.2,'Head':-math.sin(t*math.tau),'Hips':math.sin(t*math.tau)*.4}
def walk(t):
    p=idle(t)
    for i,(n,h,tail,parent) in enumerate(bones):
        if n.startswith('Leg') and not n.endswith('Foot'):
            phase=(math.pi if 'R' in n else 0)+(int(n[-1])%2*math.pi if n[-1].isdigit() else 0)
            p[n]=math.sin(t*math.tau+phase)*15
    return p
a.action('idle',60,idle);a.action('walk',30,walk)
a.action('attack',18,lambda t:{'ArmR':-48*math.sin(t*math.pi),'HandR':-22*math.sin(t*math.pi),'PincerR':{'axis':(0,0,1),'angle':30*math.sin(t*math.pi)},'Chest':4*math.sin(t*math.pi)})
a.action('skill',24,lambda t:{'ArmR':-40*math.sin(t*math.pi),'ArmL':-40*math.sin(t*math.pi),'Chest':-5*math.sin(t*math.pi),'Head':-7*math.sin(t*math.pi)})
a.action('hurt',12,lambda t:{'Chest':-9*math.sin(t*math.pi),'Head':12*math.sin(t*math.pi),'Hips':-6*math.sin(t*math.pi)})
a.action('death',30,lambda t:{'Hips':{'axis':(0,1,0),'angle':80*min(t*1.5,1),'offset':(0,0,-.2*min(t*1.5,1))},'Head':20*min(t*1.5,1)})
a.export()
