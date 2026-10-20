"""Assemble a Meshy-rigged biped enemy WITHOUT buying clips. (2026-10-02)

Meshy's auto-rig is the same 24-bone humanoid for every body, and its clips
store per-bone local rotations, so a clip bought for one rig plays on another
(verified: the Hill Giant's hammer swing / slam / death on Tidecaller's rig,
feet stayed on the ground). This stages a merge dir with the new rig as the
BASE (glb_merge_anims takes the alphabetically-first file as the mesh -- hence
00_base.glb) plus already-owned, already-TRIMMED clips, then runs the standard
merge -> frozen+breathing idle chain.

  py -3 tools/model3d/assemble_biped.py <enemy> <clipset> [--out name_v001.glb]

clipsets (all owned, trimmed):
  brute  : hill_giant  attack(hammer swing 128) ult(ground slam 127) hurt(178) death(189)
  caster : tidecaller  attack(cast 136) skill(cast 129) + hill_giant hurt/death
  own    : <enemy>/raw/_clips/*_trim.glb (bought for this rig) + hill_giant hurt/death

Run from autobattler-rpg/. Writes assets/3d pipeline/enemy/<enemy>/<enemy>_v001.glb
"""
import os, shutil, subprocess, sys

BLENDER = "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe"
ROOT = "assets/3d pipeline/enemy"
HG = f"{ROOT}/hill_giant/raw/_merge"
TC = f"{ROOT}/tidecaller/raw/_merge"
# "own": this enemy's OWN bought clips, already trimmed (raw/_clips/*_trim.glb),
# plus the shared hurt/death -- e.g. the Triarch Hunter's archery shots.
CLIPSETS = {
    "brute":  [f"{HG}/hg_attack.glb", f"{HG}/hg_skill.glb", f"{HG}/hg_hurt.glb", f"{HG}/hg_death.glb"],
    "caster": [f"{TC}/tc_attack.glb", f"{TC}/tc_skill.glb", f"{HG}/hg_hurt.glb", f"{HG}/hg_death.glb"],
}


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout[-2000:], r.stderr[-2000:])
        raise SystemExit(f"failed: {cmd[:4]}")
    return r.stdout


def main():
    name, clipset = sys.argv[1], sys.argv[2]
    out_name = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else f"{name}_v001.glb"
    raw = f"{ROOT}/{name}/raw"
    stage = f"{raw}/_merge"
    if os.path.isdir(stage):
        shutil.rmtree(stage)
    os.makedirs(stage)
    shutil.copy(f"{raw}/{name}_rigged_v001.glb", f"{stage}/00_base.glb")
    for extra in ("running", "walking"):
        shutil.copy(f"{raw}/{name}_rigged_v001_{extra}.glb", f"{stage}/{name}_{extra}.glb")
    clips = CLIPSETS.get(clipset)
    if clipset == "own":
        own = f"{raw}/_clips"
        clips = [os.path.join(own, f) for f in sorted(os.listdir(own)) if f.endswith("_trim.glb")]
        clips += [f"{HG}/hg_hurt.glb", f"{HG}/hg_death.glb"]
    for c in clips:
        shutil.copy(c, stage)
    merged = f"{raw}/{name}_merged.glb"
    print(run([sys.executable, "tools/model3d/glb_merge_anims.py", stage, merged,
               "--tex", "1024", "--harden-bones", "RightHand,LeftHand"]).strip().splitlines()[-1])
    run([BLENDER, "-b", "--python", "tools/model3d/freeze_pose.py", "--", "--model", merged,
         "--source", "walk_slow", "--frame", "1", "--name", "idle"])
    out = f"{ROOT}/{name}/{out_name}"
    run([BLENDER, "-b", "--python", "tools/model3d/add_breathing_idle.py", "--", "--model", merged, "--out", out])
    print("wrote", out)


main()
