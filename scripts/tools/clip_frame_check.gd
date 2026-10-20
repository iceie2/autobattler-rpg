extends Node
## Every clip against the camera frame (lesson from Bloodhound v002: _frame_camera
## sizes from idle + death only, and an overhead strike clipped unnoticed).
## Counts opaque pixels on the viewport's border at 12 points through each clip.
## Any > 0 means part of the character left the frame on that sample.
##   godot --path autobattler-rpg res://scenes/tools/clip_frame_check.tscn -- --hero=RUSH
##   ... -- --enemy=create_hill_giant --sheet=<abs dir>   (enemy factory func; --sheet
##   also saves one contact sheet per clip of the raw viewport frames)

func _ready() -> void:
	var hero := "RUSH"
	var enemy := ""
	var phase := 1
	var sheet_dir := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hero="):
			hero = a.substr(7)
		elif a.begins_with("--enemy="):
			enemy = a.substr(8)
		elif a.begins_with("--phase="):
			phase = int(a.substr(8))
		elif a.begins_with("--sheet="):
			sheet_dir = a.substr(8)
	var u: VisualUnit
	if enemy != "":
		hero = enemy
		u = Callable(EnemyFactory, enemy).call()
	else:
		var cls: int = UnitBase.UnitClass.keys().find(hero)
		u = UnitFactory.create_unit(cls, UnitBase.Element.NORMAL, true)
	if enemy == "create_triarch":
		for i in range(1, phase): EnemyFactory.advance_triarch_phase(u)
		hero += "_phase%d" % phase
	u.set_meta("anim_preview_lock", true)
	add_child(u)
	await get_tree().process_frame
	var m: Model3DSprite = u.model3d
	var worst := 0
	for clip in m.get_animation_list():
		if not m.has_animation(clip):
			continue
		m.play(clip)
		var length: float = m.animation_length(clip)
		var hits: Array = []
		var frames: Array = []
		for i in 12:
			m._anim.seek(length * float(i) / 11.0, true)
			m._anim.pause()
			for k in 2:
				await RenderingServer.frame_post_draw
			var img := m._viewport.get_texture().get_image()
			var w := img.get_width()
			var h := img.get_height()
			var n := 0
			for x in w:
				if img.get_pixel(x, 0).a > 0.5: n += 1
				if img.get_pixel(x, h - 1).a > 0.5: n += 1
			for y in h:
				if img.get_pixel(0, y).a > 0.5: n += 1
				if img.get_pixel(w - 1, y).a > 0.5: n += 1
			hits.append(n)
			if sheet_dir != "":
				frames.append(img)
			worst = maxi(worst, n)
		if sheet_dir != "" and not frames.is_empty():
			var fw: int = frames[0].get_width()
			var fh: int = frames[0].get_height()
			var sheet := Image.create(fw * 6, fh * 2, false, Image.FORMAT_RGBA8)
			sheet.fill(Color(0.35, 0.5, 0.3))
			for k in frames.size():
				var f: Image = frames[k]
				f.convert(Image.FORMAT_RGBA8)
				sheet.blend_rect(f, Rect2i(0, 0, fw, fh), Vector2i((k % 6) * fw, (k / 6) * fh))
				# frame border, so a cut-off reads as touching the line
				for x in fw:
					sheet.set_pixel((k % 6) * fw + x, (k / 6) * fh, Color.RED)
				for y in fh:
					sheet.set_pixel((k % 6) * fw, (k / 6) * fh + y, Color.RED)
			sheet.save_png(sheet_dir.path_join("%s_%s.png" % [hero, clip]))
		print("CLIP_FRAME %-10s %-10s border_px per sample %s" % [hero, clip, str(hits)])
	print("CLIP_FRAME_DONE %s worst=%d" % [hero, worst])
	get_tree().quit()
