"""Copy ONE animation from a separate raw Meshy export into an already-merged
character .glb, replacing a clip of the same name if one exists. Pure Python
glTF surgery (reuses glb_merge_anims.py's read_glb/write_glb/copy_animation),
no Blender needed — this is exactly the node-name-matching copy the merge
tool already does for a fresh character, just run once against an existing
one instead of rebuilding the whole file.

For the case where a hero picked up a real Meshy animation for a clip that
was previously a workaround (e.g. Headhunter's idle, hand-frozen from a
different clip because Meshy hadn't generated a real one yet — see
freeze_pose.py). Requires the new export's rig to match the existing
character's bones by NAME (verify with Blender first if unsure: same bone
list, same vertex count means the same underlying model, just re-exported
with one more animation).

  py -3 replace_clip.py \
      --character "assets/3d pipeline/hero/headhunter/headhunter.glb" \
      --source "assets/3d pipeline/hero/headhunter/Meshy_AI_..._Idle_9_withSkin.glb" \
      --name idle
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb_merge_anims import read_glb, write_glb, copy_animation, clip_name


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--character", required=True)
    p.add_argument("--source", required=True)
    p.add_argument("--name", required=True, help="the game clip name to write this animation as")
    p.add_argument("--out")
    a = p.parse_args()

    dst_js, dst_bin = read_glb(a.character)
    src_js, src_bin = read_glb(a.source)

    src_anims = src_js.get("animations", [])
    if not src_anims:
        print("no animations found in %s" % a.source)
        return 1
    if len(src_anims) > 1:
        print("multiple animations in %s: %s — using the first"
              % (a.source, [x.get("name") for x in src_anims]))
    anim = src_anims[0]
    print("source clip: %r -> writing as %r" % (anim.get("name"), a.name))

    existing = [x for x in dst_js.get("animations", []) if x.get("name") == a.name]
    for x in existing:
        dst_js["animations"].remove(x)
        print("  removed existing %r clip" % a.name)

    n = copy_animation(dst_js, dst_bin, src_js, src_bin, anim, a.name)
    print("  copied %d channels" % n)

    dst_js["buffers"] = [{"byteLength": len(dst_bin)}]
    dest = a.out or a.character
    write_glb(dest, dst_js, dst_bin)
    print("wrote %s" % dest)


if __name__ == "__main__":
    main()
