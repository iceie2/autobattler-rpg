#!/usr/bin/env python3
"""Meshy API client for the hero 2D -> 3D conversion pipeline.

Drives the generation half of 3D_PIPELINE.md stage 2: concept image -> mesh ->
rig -> animation clips -> the .glb files that land in
`assets/3d pipeline/hero/<name>/raw/` for glb_merge_anims.py to consume.

WHY THIS AND NOT `meshy-cli`
    The official CLI (github.com/meshy-dev/meshy-cli) covers the same endpoints,
    but it is a Node 24+ global npm install and there is no Node runtime on this
    machine at all. Every other tool in tools/model3d/ is stdlib Python. This is
    ~1 file of urllib against a REST API; adding a Node toolchain to reach it
    costs more than it saves. Revisit if the CLI grows something we'd have to
    reimplement (resumable uploads, streaming progress).

CREDITS
    Every generating call goes through _spend(), which refuses to start when the
    balance is at or below HARD_STOP. That number is a standing instruction from
    the project owner, not a Meshy limit -- do not change it here without one.
    2026-09-19: the owner lifted the reserve ("no more 100 stop, we can use the
    full thing"), so HARD_STOP is 0 and only a genuinely empty balance blocks a
    call. It was 500, then 100, then 0; restore a floor only on their say-so.

    Verified against Meshy's pricing page 2026-09-09:

        image-to-3d, Meshy-6    30     (20 untextured, 35 for 8K)
        image-to-3d, T2 topo    15     (5 untextured, 20 for 8K)  -- much cheaper
        rigging                  5     (returns walk + run clips for free)
        animation, preset        3     per clip
        text-to-motion, swift    3     per clip
        text-to-motion, prime   10     per clip
        => ~50-60 per hero

    Two things worth remembering from that table:
      - Preset library actions are NOT free on the API even though they behave
        as free in the web app. animate() measures the real charge; see there.
      - A custom prompted motion (text-to-motion swift) costs the SAME 3 as a
        preset. So never force a bad preset fit to save credits -- there are no
        credits to save. Pick on motion quality alone.

USAGE
    # every command takes --key or reads MESHY_API_KEY
    py -3 meshy_api.py balance
    py -3 meshy_api.py library --grep hammer
    py -3 meshy_api.py image-to-3d assets/using/cross.png --out <dir> --wait
    py -3 meshy_api.py rig <model_task_id> --wait
    py -3 meshy_api.py animate <rig_task_id> --action 128 --name attack --out <dir>

    Add --dry-run to price a command without calling the API, and
    --test to force the zero-credit test key.

TEST MODE IS PARTIAL -- measured 2026-09-09, not documented by Meshy:
    balance          works, returns a sample 3550
    image-to-3d      works end to end, returns a real downloadable sample .glb
    animations/library works, full 678-action catalogue
    rigging          {"message":"This test mode is not yet supported."}
    animations       same
    So the rig and animate legs CANNOT be rehearsed for free. They are exercised
    the first time on a real key, and that is a known risk, not an oversight.
"""
import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request

BASE = "https://api.meshy.ai/openapi"
# Endpoint versions are NOT uniform: text-to-3d is v2, everything else v1.
# Discovered by 404 -- the docs do not put the version in the path they show.
VER = {"text-to-3d": "v2"}
TEST_KEY = "msy_dummy_api_key_for_test_mode_12345678"
HARD_STOP = 0

COST_IMAGE_TO_3D = 30
COST_RIG = 5
COST_ANIM = 3
COST_PROP = 5      # text-to-3d preview, smart-topology, untextured
COST_REMESH = 5
COST_MOTION = {"swift": 3, "prime": 10}
COST_T23D_PREVIEW = 20   # text-to-3d preview, meshy-6
COST_IMAGE = {"nano-banana": 3, "nano-banana-2-lite": 3, "nano-banana-2": 6,
              "nano-banana-pro": 9, "gpt-image-2": 9}
COST_TEXTURE = 10        # refine/texture pass, 2k-4k (15 for 8k)

# Rigging requires the model to FACE +Z (standard glTF forward). Getting this
# wrong at generation time is the root cause of the per-clip yaw-bias
# calibration that consumed days on Headhunter.
RIG_FORWARD_NOTE = "model must face +Z before rigging"


class MeshyError(RuntimeError):
    pass


# ── transport ────────────────────────────────────────────────────────────────

def _api_ver(path):
    return VER.get(path.split("?")[0].split("/")[0], "v1")


def _req(key, method, path, body=None, timeout=120):
    url = path if path.startswith("http") else f"{BASE}/{_api_ver(path)}/{path}"
    data = json.dumps(body).encode() if body is not None else None
    headers = {"Authorization": f"Bearer {key}"}
    if data:
        headers["Content-Type"] = "application/json"
    r = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(r, timeout=timeout) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")
        raise MeshyError(f"HTTP {e.code} {method} {path}: {detail}") from None
    if not raw:
        return None
    out = json.loads(raw)
    # The API reports some failures with HTTP 200 and a bare {"message": ...}.
    if isinstance(out, dict) and set(out) == {"message"}:
        raise MeshyError(f"{method} {path}: {out['message']}")
    return out


def balance(key):
    return int(_req(key, "GET", "balance")["balance"])


def _spend(key, cost, what):
    """Refuse to start a generation that would breach the standing hard stop."""
    if key == TEST_KEY:
        print(f"[test] {what}: would cost {cost} credits (test key, no charge)")
        return None
    bal = balance(key)
    print(f"[credits] balance {bal}, {what} costs ~{cost}")
    if bal <= HARD_STOP:
        raise MeshyError(
            f"HARD STOP: balance {bal} is at or below {HARD_STOP}. "
            "Stopping and reporting, per standing instruction."
        )
    if bal - cost <= HARD_STOP:
        raise MeshyError(
            f"HARD STOP: {what} would leave {bal - cost}, at or below "
            f"{HARD_STOP}. Not starting it."
        )
    return bal


# ── polling ──────────────────────────────────────────────────────────────────

def wait(key, kind, task_id, poll=10, timeout=3600):
    """Block until a task leaves PENDING/IN_PROGRESS. Returns the task dict."""
    t0 = time.time()
    last = None
    while True:
        t = _req(key, "GET", f"{kind}/{task_id}")
        st, pr = t.get("status"), t.get("progress", 0)
        if (st, pr) != last:
            print(f"  {kind} {task_id[:8]} {st} {pr}%")
            last = (st, pr)
        if st == "SUCCEEDED":
            return t
        if st in ("FAILED", "CANCELED", "EXPIRED"):
            # Credits are refunded on task failure -- report, do not silently retry.
            raise MeshyError(f"{kind} {task_id} {st}: {t.get('task_error')}")
        if time.time() - t0 > timeout:
            raise MeshyError(f"{kind} {task_id} timed out after {timeout}s (last {st})")
        time.sleep(poll)


# ── generation ───────────────────────────────────────────────────────────────

def image_data_uri(path):
    """Inline the concept art rather than publishing it to a public host."""
    mime = mimetypes.guess_type(path)[0] or "image/png"
    return f"data:{mime};base64," + base64.b64encode(open(path, "rb").read()).decode()


def image_to_3d(key, image_path, polycount=10000, texture=True,
                ai_model="meshy-t2", symmetry="auto"):
    """Concept image -> textured mesh. THE DEFAULTS HERE ARE THE POINT.

    ai_model="meshy-t2" (Smart Topology) is the right choice for a game
    character and it is not close:

                        credits   faces out        then what
        meshy-6            30     ~440,000         + 5 remesh, + decimation
        meshy-t2           15     <= 15,000        nothing

    Cross was generated on meshy-6 first (2026-09-09) and came back at 440,046
    triangles -- over the rigging endpoint's own 300,000-face input limit and
    ~20x the game's 10-25k budget -- so it needed a 5-credit remesh on top.
    35 credits to reach a worse place than 15 buys directly. meshy-t2 also emits
    QUAD topology, which is what you want under a rig, and its polycount ceiling
    (15,000) sits exactly in the game's budget so the number cannot run away.

    meshy-t2 emits TRIANGLES, not quads (the API refuses topology="quad" for
    it). That is fine under a rig here -- nothing downstream subdivides.

    Reach for meshy-6 only when a character genuinely needs the density -- and
    measure the shipped roster before believing that it does. Bouncer is
    104,327 tris but he is the outlier, not the norm: headhunter 18,421,
    bloodhound 9,329.

    NOTE: meshy-t2 REQUIRES model_type="smart-topology"; the API rejects the
    model id on its own. target_polycount must be 100-15000 for t2.
    """
    smart = ai_model == "meshy-t2"
    cost = (15 if texture else 5) if smart else (COST_IMAGE_TO_3D if texture else 20)
    _spend(key, cost, f"image-to-3d {ai_model} ({os.path.basename(image_path)})")
    body = {
        "image_url": image_data_uri(image_path),
        "should_texture": texture,
        "ai_model": ai_model,
        "target_polycount": min(polycount, 15000) if smart else polycount,
        "symmetry_mode": symmetry,
    }
    if smart:
        # Smart Topology is triangle-only -- sending topology="quad" is a hard
        # 400 ("quad is not supported for meshy-t2"), measured 2026-09-10.
        body["model_type"] = "smart-topology"
    else:
        body["topology"] = "quad"
    return _req(key, "POST", "image-to-3d", body)["result"]


def text_to_image(key, prompt, ai_model="nano-banana-pro", pose="a-pose",
                  aspect="3:4", remove_bg=True):
    """Generate the CONCEPT IMAGE for a character, in-house, as stage 1.

    3D_PIPELINE.md sends this stage to Gemini by hand. Meshy hosts the same
    family of models (the `nano-banana` options ARE Gemini) behind
    POST /openapi/v1/text-to-image, which makes stage 1 automatable and removes
    the only step of the whole conversion that needed a human in the loop.

    THE REASON TO USE THIS OVER text-to-3d FOR A BODY -- `pose_mode`, which
    takes exactly [a-pose, t-pose]. The first Cross attempt went straight to
    text-to-3d and came back in a splay-armed shrug with a tail, because a
    prompt asking for an A-pose and "NO TAIL" is a request, not a constraint.
    Here the A-pose is enforced by the endpoint. Generating an image first and
    feeding image-to-3d also costs the SAME as going direct:

        text-to-image 9 + image-to-3d 30 = 39   <- and reviewable at 9
        text-to-3d 20 + texture 10       = 30

    9 more, and in exchange the pose is guaranteed, the concept can be rejected
    for 9 instead of 20, and identity (species, tabard, emblem) is carried by a
    picture rather than by adjectives, which is the failure mode that killed
    attempt one.

    Costs: nano-banana 3, nano-banana-2 6, nano-banana-pro / gpt-image-2 9.
    """
    cost = COST_IMAGE.get(ai_model, 9)
    _spend(key, cost, f"text-to-image {ai_model} ({prompt[:32]}...)")
    body = {"ai_model": ai_model, "prompt": prompt, "pose_mode": pose,
            "aspect_ratio": aspect, "remove_background": remove_bg}
    return _req(key, "POST", "text-to-image", body)["result"]


def download_image(task, out_path):
    """Save a text-to-image result. The task exposes image_url(s), not model_urls."""
    url = task.get("image_url") or (task.get("image_urls") or [None])[0]
    if not url:
        raise MeshyError(f"image task {task.get('id')} has no image url: "
                         + json.dumps(task)[:400])
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as r, open(out_path, "wb") as f:
        f.write(r.read())
    print(f"  saved {out_path} ({os.path.getsize(out_path) / 1e3:.0f} KB)")
    return out_path


def text_to_3d_character(key, prompt, polycount=20000, ai_model="meshy-6"):
    """Generate a CHARACTER body straight from a prompt, skipping concept art.

    3D_PIPELINE.md documents the chain as Gemini concept image -> image-to-3d,
    which is right when on-model art already exists and must be matched. It is
    not a requirement of the API. Where no usable concept exists -- or the one
    that exists is in a combat stance with props crossing the body, which is
    what rigs badly -- text-to-3d reaches the same place for the same money:

        text-to-3d preview 20 + texture 10 = 30
        image-to-3d textured             = 30

    and it buys pose control (a clean A-pose, hands empty and clear of the hips)
    that an existing piece of 2D art cannot be talked into.

    DO NOT put the 2D sprite style block in this prompt. "thick black outline",
    "flat cel-shaded", "solid green background" describe how a SPRITE is drawn;
    asked of a mesh generator they ask for geometry shaped like an outline. The
    toon shading and outline are applied in-engine (Model3DSprite toon=true,
    outline_px=2.0). Describe FORM and MATERIAL here, nothing about rendering.

    Two stages, and that is an advantage: the preview is untextured, so the
    silhouette and pose can be judged for 20 before committing the texture 10.
    """
    _spend(key, COST_T23D_PREVIEW, f"text-to-3d preview ({prompt[:40]}...)")
    body = {
        "mode": "preview",
        "prompt": prompt,
        "ai_model": ai_model,
        "topology": "quad",
        "target_polycount": polycount,
        "should_remesh": True,
    }
    return _req(key, "POST", "text-to-3d", body)["result"]


def text_to_3d_prop(key, prompt, polycount=6000):
    """Prompt -> a single untextured hard-surface prop (weapon, tool, shield).

    Cheapest useful call in the pipeline at 5 credits: text-to-3d preview on
    meshy-t2 smart-topology, no texture stage. Props do NOT need a texture --
    they arrive with zero materials either way, and the pipeline assigns flat
    colours in Blender (rig_weapon.py --color / a per-slot material split),
    which is what the toon shader wants anyway. Paying 10 for a texture that is
    then overridden is pure waste.

    Smart-topology is triangle-only and caps at 15000; 6000 is plenty for a
    prop that ships at ~171 px on screen.
    """
    _spend(key, COST_PROP, f"prop ({prompt[:40]}...)")
    body = {
        "mode": "preview",
        "prompt": prompt,
        "ai_model": "meshy-t2",
        "model_type": "smart-topology",
        "target_polycount": min(polycount, 15000),
        "should_remesh": True,
    }
    return _req(key, "POST", "text-to-3d", body)["result"]


def texture_3d(key, preview_task_id, resolution="4k"):
    """Refine stage: texture a finished text-to-3d preview. 10 credits at 2k/4k.

    Meshy albedo comes back too dark for this game's flat board -- gamma-correct
    the COLOUR map only afterwards (brighten_texture.py), never the normal or
    metallic-roughness maps.
    """
    _spend(key, COST_TEXTURE, f"texture ({preview_task_id[:8]})")
    return _req(key, "POST", "text-to-3d",
                {"mode": "refine", "preview_task_id": preview_task_id,
                 "texture_resolution": resolution})["result"]


def text_to_motion(key, prompt, duration=2.0, mode="swift"):
    """Generate a CUSTOM motion from a text prompt. swift 3 credits, prime 10.

    WHY THIS EXISTS ALONGSIDE THE PRESET LIBRARY. Motions authored in Meshy's
    WEB app are invisible to the API: /openapi/v1/text-to-motion lists [] under
    every page/sort/status parameter, and no project, workspace or asset route
    exists to bridge the two. The API key and the web session are separate asset
    scopes. So a motion that must be usable from the pipeline has to be created
    HERE, through the key, not in the browser.

    The result's task id is then passed to animate_motion() as motion_task_id.
    /animations takes action_id OR motion_task_id, never both.

    DURATION IS CLAMPED BY MESHY to 2.0-10.0 seconds in 0.5 steps. A game attack
    is usually well under 2s, so expect to retime the result down afterwards
    (retime_clip.py) rather than getting the length you asked for.
    """
    d = max(2.0, min(10.0, round(duration * 2) / 2))
    _spend(key, COST_MOTION.get(mode, 3), f"text-to-motion {mode} {d}s")
    return _req(key, "POST", "text-to-motion",
                {"prompt": prompt, "duration": d, "mode": mode})["result"]


def animate_motion(key, rig_task_id, motion_task_id):
    """Apply a CUSTOM motion (not a preset action) to a rigged model."""
    before = _spend(key, COST_ANIM, f"animate from motion {motion_task_id[:8]}")
    tid = _req(key, "POST", "animations",
               {"rig_task_id": rig_task_id, "motion_task_id": motion_task_id})["result"]
    if before is not None:
        after = balance(key)
        print(f"[credits] charged {before - after} ({before} -> {after})")
    return tid


def remesh(key, input_task_id, polycount=20000, topology="quad"):
    """Reduce a generated mesh's polycount. 5 credits.

    NEEDED, not optional: image-to-3d IGNORES target_polycount unless remeshing
    is requested, and Cross's body came back at 440,046 triangles. That is over
    TWO problems at once -- the rigging endpoint refuses inputs above 300,000
    faces, and the game's own budget is 10-25k.

    Do this Meshy-side rather than decimating in Blender. Not for quality: for
    the workflow. Rigging accepts an input_task_id OR a public model_url, and a
    locally-edited .glb has neither -- editing the mesh here means losing the
    ability to rig it at all without hosting the file somewhere public. Every
    mesh edit therefore has to happen AFTER rigging, or through the API.
    """
    _spend(key, COST_REMESH, f"remesh -> {polycount} ({input_task_id[:8]})")
    return _req(key, "POST", "remesh",
                {"input_task_id": input_task_id, "target_polycount": polycount,
                 "topology": topology, "target_formats": ["glb"]})["result"]


def rig(key, model_task_id, height=1.7):
    """Auto-rig a generated mesh.

    NOTE the rig is a FIXED 24-joint biped -- Hips, legs, 3 spine, arms, neck,
    Head, head_end, headfront. Measured identical across bouncer, bloodhound and
    headhunter, including bloodhound who is a dog. There are no tail, finger,
    cloak or hood bones and asking for them does nothing. Check the concept art
    for appendages BEFORE generating; that geometry cannot articulate.
    """
    _spend(key, COST_RIG, f"rigging ({model_task_id[:8]}) -- {RIG_FORWARD_NOTE}")
    return _req(key, "POST", "rigging",
                {"input_task_id": model_task_id, "character_height": height})["result"]


def animate(key, rig_task_id, action_id):
    """Apply one preset library action to a rigged model. See library().

    COST, and why this measures instead of assuming: it is easy to believe the
    678-action library is free, because in the WEB APP it effectively is --
    browsing and applying stock animations comes with the subscription. The API
    is a different billing surface and meters every task. Meshy's pricing page
    lists "Animation (preset actions): 3 credits", and the endpoint's own task
    response carries consumed_credits. Same content, different meter.

    So this does not take the docs' word for it either: it reads the balance
    before and after and prints what was ACTUALLY charged. If the real number
    ever disagrees with COST_ANIM, the per-hero budget is wrong and every
    estimate built on it is wrong -- surface that on clip one, not clip six.
    """
    before = _spend(key, COST_ANIM, f"animation action {action_id}")
    tid = _req(key, "POST", "animations",
               {"rig_task_id": rig_task_id, "action_id": int(action_id)})["result"]
    if before is not None:
        after = balance(key)
        charged = before - after
        flag = "" if charged == COST_ANIM else f"  <-- EXPECTED {COST_ANIM}, BUDGET IS WRONG"
        print(f"[credits] action {action_id} charged {charged} ({before} -> {after}){flag}")
    return tid


def library(key, page_size=100, max_pages=20):
    """The preset action catalogue: 678 unique actions, each with a preview GIF.

    Paging repeats entries, so dedupe by action_id. The preview_url is the
    cheapest review in this whole pipeline -- judge a clip from its GIF before
    spending 3 credits to find out it does not hold at the extreme.
    """
    seen = {}
    for page in range(1, max_pages + 1):
        d = _req(key, "GET", f"animations/library?page_size={page_size}&page_num={page}")
        if not d:
            break
        for a in d:
            seen[a["action_id"]] = a
    return sorted(seen.values(), key=lambda a: a["action_id"])


def download(task, out_dir, name, fmt="glb"):
    """Save a finished task's model.

    Result shapes differ per endpoint and none of it is documented:
      image-to-3d / text-to-3d / remesh -> task["model_urls"][fmt]
      rigging -> task["result"]["rigged_character_glb_url"], with the free
                 walk and run clips under result["basic_animations"].
    """
    res = task.get("result") or {}
    url = ((task.get("model_urls") or {}).get(fmt)
           or task.get("model_url")
           or res.get(f"rigged_character_{fmt}_url")
           or res.get(f"animation_{fmt}_url"))
    if not url:
        raise MeshyError(f"task {task.get('id')} has no {fmt} url; keys="
                         + ",".join(list(task) + list(res)))
    os.makedirs(out_dir, exist_ok=True)
    dest = os.path.join(out_dir, f"{name}.{fmt}")
    with urllib.request.urlopen(url, timeout=600) as r, open(dest, "wb") as f:
        f.write(r.read())
    print(f"  saved {dest} ({os.path.getsize(dest) / 1e6:.1f} MB)")
    return dest


def download_rig_bundle(task, out_dir, name):
    """Rigged body PLUS the walk/run clips rigging throws in for free.

    Those two are worth taking every time: they cost nothing and cover the
    game's `walk` slot outright (the merge maps Running -> walk, since units
    cross the board fast enough that Meshy's walk reads sluggish).
    """
    paths = [download(task, out_dir, name)]
    basic = ((task.get("result") or {}).get("basic_animations") or {})
    for clip in ("walking", "running"):
        url = basic.get(f"{clip}_glb_url")
        if not url:
            print(f"  ! no free {clip} clip in this rig task")
            continue
        dest = os.path.join(out_dir, f"{name}_{clip}.glb")
        with urllib.request.urlopen(url, timeout=600) as r, open(dest, "wb") as f:
            f.write(r.read())
        print(f"  saved {dest} ({os.path.getsize(dest) / 1e6:.1f} MB)  [free]")
        paths.append(dest)
    return paths


# ── cli ──────────────────────────────────────────────────────────────────────

def _key(args):
    if args.test:
        return TEST_KEY
    k = args.key or os.environ.get("MESHY_API_KEY", "")
    if not k:
        sys.exit("MESHY_API_KEY is not set (and no --key given). Use --test for "
                 "the zero-credit test key.")
    return k


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--key")
    p.add_argument("--test", action="store_true", help="use the zero-credit test key")
    p.add_argument("--dry-run", action="store_true", help="price it, do not call")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("balance")

    q = sub.add_parser("library")
    q.add_argument("--grep", default="", help="case-insensitive name filter")

    i = sub.add_parser("image-to-3d")
    i.add_argument("image")
    i.add_argument("--out", required=True)
    i.add_argument("--name", default="model")
    i.add_argument("--polycount", type=int, default=10000)
    i.add_argument("--ai-model", dest="ai_model", default="meshy-t2")
    i.add_argument("--no-texture", action="store_true")
    i.add_argument("--wait", action="store_true")

    im = sub.add_parser("concept")
    im.add_argument("prompt")
    im.add_argument("--out", required=True)
    im.add_argument("--model", default="nano-banana-pro")
    im.add_argument("--pose", default="a-pose", choices=["a-pose", "t-pose"])
    im.add_argument("--aspect", default="3:4")

    ch = sub.add_parser("character")
    ch.add_argument("prompt")
    ch.add_argument("--out", required=True)
    ch.add_argument("--name", required=True)
    ch.add_argument("--polycount", type=int, default=20000)

    tx = sub.add_parser("texture")
    tx.add_argument("preview_task_id")
    tx.add_argument("--out", required=True)
    tx.add_argument("--name", required=True)

    w = sub.add_parser("prop")
    w.add_argument("prompt")
    w.add_argument("--out", required=True)
    w.add_argument("--name", required=True)
    w.add_argument("--polycount", type=int, default=6000)

    rm = sub.add_parser("remesh")
    rm.add_argument("task_id")
    rm.add_argument("--out", required=True)
    rm.add_argument("--name", required=True)
    rm.add_argument("--polycount", type=int, default=20000)

    r = sub.add_parser("rig")
    r.add_argument("task_id")
    r.add_argument("--out")
    r.add_argument("--name", default="rigged")
    r.add_argument("--height", type=float, default=1.7)
    r.add_argument("--wait", action="store_true")

    a = sub.add_parser("animate")
    a.add_argument("task_id", help="RIG task id")
    a.add_argument("--action", type=int, required=True)
    a.add_argument("--name", required=True, help="clip name, e.g. attack")
    a.add_argument("--out", required=True)
    a.add_argument("--wait", action="store_true", default=True)

    mo = sub.add_parser("motion", help="custom text-to-motion, then apply to a rig")
    mo.add_argument("prompt")
    mo.add_argument("--rig", required=True, help="RIG task id")
    mo.add_argument("--name", required=True, help="clip name, e.g. attack")
    mo.add_argument("--out", required=True)
    mo.add_argument("--duration", type=float, default=2.0)
    mo.add_argument("--mode", default="swift", choices=["swift", "prime"])

    g = sub.add_parser("get")
    g.add_argument("kind", choices=["image-to-3d", "rigging", "animations"])
    g.add_argument("task_id")

    args = p.parse_args()
    key = _key(args)

    if args.cmd == "balance":
        print(balance(key))

    elif args.cmd == "library":
        for x in library(key):
            if args.grep.lower() in x["name"].lower():
                print(f"{x['action_id']:5d}  {x['name'][:44]:44s} {x['category']}/{x['sub_category']}")

    elif args.cmd == "image-to-3d":
        if args.dry_run:
            print(f"would spend {COST_IMAGE_TO_3D if not args.no_texture else 20}")
            return
        tid = image_to_3d(key, args.image, args.polycount,
                          not args.no_texture, args.ai_model)
        print("task", tid)
        if args.wait:
            download(wait(key, "image-to-3d", tid), args.out, args.name)

    elif args.cmd == "concept":
        if args.dry_run:
            print(f"would spend {COST_IMAGE.get(args.model, 9)}")
            return
        tid = text_to_image(key, args.prompt, args.model, args.pose, args.aspect)
        print("task", tid)
        download_image(wait(key, "text-to-image", tid), args.out)

    elif args.cmd == "character":
        if args.dry_run:
            print(f"would spend {COST_T23D_PREVIEW}")
            return
        tid = text_to_3d_character(key, args.prompt, args.polycount)
        print("PREVIEW TASK", tid)
        download(wait(key, "text-to-3d", tid), args.out, args.name)

    elif args.cmd == "texture":
        if args.dry_run:
            print(f"would spend {COST_TEXTURE}")
            return
        tid = texture_3d(key, args.preview_task_id)
        print("REFINE TASK", tid)
        download(wait(key, "text-to-3d", tid), args.out, args.name)

    elif args.cmd == "prop":
        if args.dry_run:
            print(f"would spend {COST_PROP}")
            return
        tid = text_to_3d_prop(key, args.prompt, args.polycount)
        print("task", tid)
        download(wait(key, "text-to-3d", tid), args.out, args.name)

    elif args.cmd == "remesh":
        if args.dry_run:
            print(f"would spend {COST_REMESH}")
            return
        tid = remesh(key, args.task_id, args.polycount)
        print("REMESH TASK", tid)
        download(wait(key, "remesh", tid), args.out, args.name)

    elif args.cmd == "rig":
        if args.dry_run:
            print(f"would spend {COST_RIG}")
            return
        tid = rig(key, args.task_id, args.height)
        print("task", tid)
        if args.wait and args.out:
            download_rig_bundle(wait(key, "rigging", tid), args.out, args.name)

    elif args.cmd == "animate":
        if args.dry_run:
            print(f"would spend {COST_ANIM}")
            return
        tid = animate(key, args.task_id, args.action)
        print("task", tid)
        download(wait(key, "animations", tid), args.out, args.name)

    elif args.cmd == "motion":
        # Two charges, not one: the motion itself (swift 3 / prime 10) and the
        # animations call that retargets it onto the rig (3). Both are printed.
        if args.dry_run:
            print(f"would spend {COST_MOTION.get(args.mode, 3)} + {COST_ANIM}")
            return
        mid = text_to_motion(key, args.prompt, args.duration, args.mode)
        print("motion task", mid)
        wait(key, "text-to-motion", mid)
        aid = animate_motion(key, args.rig, mid)
        print("animation task", aid)
        download(wait(key, "animations", aid), args.out, args.name)

    elif args.cmd == "get":
        print(json.dumps(_req(key, "GET", f"{args.kind}/{args.task_id}"), indent=1)[:4000])


if __name__ == "__main__":
    main()
