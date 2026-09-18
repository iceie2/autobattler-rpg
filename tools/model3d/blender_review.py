"""Open a merged character .glb in Blender, ready to review.

Removes the five setup steps that stand between importing a character and
actually watching its animations:

  1. Deletes the `Icosphere` Blender's own glTF importer adds. It lives in a
     collection named `glTF_not_exported`, is 2.0 units across against a 1.54
     unit character, and therefore COMPLETELY HIDES the model — import without
     removing it and all you see is a grey ball.
  2. Makes the ARMATURE the active object. Clicking the character in the
     viewport selects the mesh instead, and the mesh has no animation data, so
     the Action Editor shows an empty "New" button and no clips.
  3. Assigns an action, so the rig is posed instead of sitting in its rest pose.
  4. Sets the scene frame range to that clip's real keyframe extents.
  5. Keeps the range in sync FOREVER — pick a different clip from the Action
     Editor dropdown and the range follows automatically. This is the one that
     matters: without it every clip switch needs a manual End value, and the
     range is what decides whether you are watching the animation or watching
     the animation plus four seconds of nothing.

Opens on the Animation workspace with the clip list printed to the console.

Usage (note the `--`, and quote the path — it contains a space):

  "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" \
      --python tools/model3d/blender_review.py \
      -- "assets/3d pipeline/hero/bouncer/bouncer.glb" [clip]

Or use tools/model3d/review_3d.bat, which takes just the character name.
"""
import sys
import bpy

DEFAULT_CLIP = "idle"
SCAFFOLD_COLLECTION = "glTF_not_exported"

# Set by _setup, read by the handler; module-level so the handler survives.
_armature = None
_mesh = None
_last_action = None


def _args():
    argv = sys.argv
    return argv[argv.index("--") + 1:] if "--" in argv else []


def _action_range(action):
    """Whole-frame range covering a clip's real keyframe extents.

    The glTF importer starts clips just before frame 1 (0.8, not 1.0), so this
    floors the start and ceils the end rather than rounding — rounding would
    clip a frame off each end of every animation.
    """
    lo, hi = action.frame_range
    return max(1, int(lo)), max(int(lo) + 1, int(hi + 0.999))


def _bind_slot(ad, action, id_type):
    """Bind the slot of `action` matching `id_type` ('OBJECT', 'KEY', ...).

    A slotted action can carry more than one slot — e.g. make_ult_animation.py
    folds the armature's pose/scale animation and the mesh's shape-key value
    animation into ONE action with two slots. Blindly picking slots[0] (as a
    single-slot assumption would) binds the wrong slot to the wrong ID: it
    looks correctly assigned in the UI, but that ID simply never animates.
    Matching on target_id_type is what makes both halves actually play.
    """
    slots = getattr(action, "slots", None)
    if not slots:
        return
    slot = next((s for s in slots if s.target_id_type == id_type), slots[0])
    ad.action_slot = slot


def _apply_action(arm, mesh, action):
    ad = arm.animation_data or arm.animation_data_create()
    ad.action = action
    # Blender 4.4+ actions are "slotted"; assigning the action does not always
    # bind a slot, and an unbound slot animates nothing at all while still
    # looking correctly assigned in the UI.
    if hasattr(ad, "action_slot"):
        _bind_slot(ad, action, "OBJECT")

    # The `bulk` shape key (if any) lives on the MESH's own animation_data, not
    # the armature's — a separate ID, so it needs its own action assignment.
    # Without this the morph value silently stays frozen at 0 forever: nothing
    # errors, the Action Editor looks right, the character just never widens.
    keys = mesh.data.shape_keys if mesh else None
    if keys is not None:
        key_slot = next((s for s in getattr(action, "slots", []) or []
                          if s.target_id_type == "KEY"), None)
        kad = keys.animation_data or (keys.animation_data_create() if key_slot else None)
        if kad is not None:
            if key_slot is not None:
                kad.action = action
                if hasattr(kad, "action_slot"):
                    kad.action_slot = key_slot
            elif kad.action is not None:
                # Switching to a clip with no shape-key animation: clear the
                # old one so a stale morph value doesn't bleed into this clip.
                kad.action = None

    start, end = _action_range(action)
    sc = bpy.context.scene
    sc.frame_start, sc.frame_end = start, end
    sc.frame_set(start)
    return start, end


@bpy.app.handlers.persistent
def _sync_range(_scene, _depsgraph=None):
    """Follow the Action Editor: when the clip changes, retarget the range."""
    global _last_action
    if not (_armature and _armature.animation_data):
        return
    act = _armature.animation_data.action
    if act is None or act.name == _last_action:
        return
    _last_action = act.name
    # Re-run the full bind, not just the frame range: switching TO a clip with
    # a shape-key slot (or AWAY from one) needs the mesh's animation_data
    # updated too, or the morph keeps whatever value the previous clip left it.
    start, end = _apply_action(_armature, _mesh, act)
    print("[review] %s -> frames %d-%d" % (act.name, start, end))


def _setup_ui():
    """Make the opened scene actually reviewable. Runs on the first idle tick.

    Fixes three things that otherwise make a correctly-loaded character look
    broken:

    * The bottom editor opens as a **Dope Sheet**, not an Action Editor, and its
      "Only Show Selected" filter is on by default — so with no bone selected the
      keyframe area is EMPTY and it reads as a clip with no animation.
    * The viewport frames the whole scene, and Meshy rigs carry a 0.01 object
      scale with bones drawn at their own size, so the armature renders ~7x
      larger than the character. You get a screenful of spiky octahedrons with
      the actual model a few pixels wide off to one side.
    * Blender can land in Pose Mode, where clicking does something different
      from what a reviewer expects.
    """
    ctx = bpy.context
    win = getattr(ctx, "window", None)
    if win is None:
        return None

    if _armature:
        _armature.show_in_front = False
        if _armature.mode != "OBJECT":
            try:
                with ctx.temp_override(active_object=_armature, object=_armature):
                    bpy.ops.object.mode_set(mode="OBJECT")
            except Exception:
                pass

    mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)

    for area in win.screen.areas:
        if area.type == "DOPESHEET_EDITOR":
            space = area.spaces.active
            space.mode = "ACTION"
            # Show every channel, not just the selected bone's.
            space.dopesheet.show_only_selected = False
        elif area.type == "VIEW_3D" and mesh is not None:
            region = next((r for r in area.regions if r.type == "WINDOW"), None)
            if region is None:
                continue
            # Hide bones FROM THIS VIEWPORT rather than hiding/altering the
            # armature object. Meshy rigs sit at 0.01 object scale with bones
            # authored at 100x, so every bone display type draws enormous — as
            # sticks they cross the whole screen and bury the character. This
            # flag is viewport-only: the armature stays active, selectable and
            # deforming, so the Action Editor keeps targeting it.
            area.spaces.active.show_object_viewport_armature = False
            # Frame the CHARACTER, not the oversized armature display.
            for o in bpy.data.objects:
                o.select_set(o is mesh)
            try:
                with ctx.temp_override(area=area, region=region):
                    bpy.ops.view3d.view_selected()
            except Exception:
                pass
            # Hand selection back to the armature so the Action Editor targets it.
            for o in bpy.data.objects:
                o.select_set(o is _armature)
            if _armature:
                bpy.context.view_layer.objects.active = _armature
    return None   # run once


def _setup():
    global _armature, _mesh, _last_action
    args = _args()
    if not args:
        print("[review] no .glb given")
        return
    path, want = args[0], (args[1] if len(args) > 1 else DEFAULT_CLIP)

    # Suppress the startup splash. It overlays the scene we are about to build,
    # and its "New File > General" button would RESET the file and silently throw
    # the import away. Session-only: we never call wm.save_userpref(), so the
    # user's own preference is untouched.
    try:
        bpy.context.preferences.view.show_splash = False
    except Exception:
        pass

    # Wipe the file back to empty by hand rather than read_homefile():
    # reloading the startup file from inside a --python startup script re-triggers
    # the splash and resets the window layout underneath us.
    #
    # ACTIONS MUST BE WIPED TOO. If the opened .blend already holds actions --
    # which happens the moment anyone presses Ctrl+S while reviewing -- the
    # import lands on top of them and every clip appears twice, as `idle` and
    # `idle.001`. Wiping makes the tool immune to whatever state the base file
    # is in.
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for act in list(bpy.data.actions):
        act.use_fake_user = False
        bpy.data.actions.remove(act)
    for arm in list(bpy.data.armatures):
        bpy.data.armatures.remove(arm)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)

    bpy.ops.import_scene.gltf(filepath=path)

    # 1. Drop Blender's import scaffolding — the objects AND the now-empty
    #    collection, which otherwise sits in the outliner looking meaningful.
    removed = 0
    for ob in list(bpy.data.objects):
        if any(c.name == SCAFFOLD_COLLECTION for c in ob.users_collection):
            bpy.data.objects.remove(ob, do_unlink=True)
            removed += 1
    scaffold = bpy.data.collections.get(SCAFFOLD_COLLECTION)
    if scaffold is not None:
        bpy.data.collections.remove(scaffold)

    arms = [o for o in bpy.data.objects if o.type == "ARMATURE"]
    if not arms:
        print("[review] no armature in %s" % path)
        return
    _armature = arms[0]
    _mesh = next((o for o in bpy.data.objects if o.type == "MESH"), None)

    # 2. Armature active + selected, so the Action Editor targets it.
    bpy.ops.object.select_all(action="DESELECT")
    _armature.select_set(True)
    bpy.context.view_layer.objects.active = _armature

    # The importer parks every clip in a muted NLA track. Leave them muted so
    # the Action Editor is authoritative; an unmuted track would override it.
    if _armature.animation_data:
        for tr in _armature.animation_data.nla_tracks:
            tr.mute = True

    # 3 + 4. Assign the clip and frame it. Keep every action alive across
    # save/reload — imported actions arrive with no fake user and can be purged.
    for a in bpy.data.actions:
        a.use_fake_user = True

    clips = sorted(bpy.data.actions.keys())
    action = bpy.data.actions.get(want) or bpy.data.actions.get(clips[0])
    start, end = _apply_action(_armature, _mesh, action)
    _last_action = action.name

    # 5. Keep the range following the Action Editor from here on.
    if _sync_range not in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.append(_sync_range)

    # No window when Blender runs --background (the test harness does), so this
    # is optional rather than fatal.
    win = getattr(bpy.context, "window", None)
    if win is not None:
        for ws in ("Animation", "Layout"):
            if ws in bpy.data.workspaces:
                win.workspace = bpy.data.workspaces[ws]
                break
        # The editors do not exist yet at startup-script time; a timer runs the
        # UI setup on the first idle tick, once the workspace is really built.
        bpy.app.timers.register(_setup_ui, first_interval=0.15)

    fps = bpy.context.scene.render.fps
    print("\n" + "=" * 58)
    print(" %s   (%d scaffold object(s) removed)" % (path.split("/")[-1], removed))
    print("=" * 58)
    for name in clips:
        lo, hi = _action_range(bpy.data.actions[name])
        print("   %-14s %3d frames   %5.2fs%s"
              % (name, hi - lo + 1, (hi - lo + 1) / float(fps),
                 "   <- showing" if name == action.name else ""))
    print("\n Pick another clip in the Action Editor dropdown —")
    print(" the frame range retargets itself. Space to play.\n")


_setup()
