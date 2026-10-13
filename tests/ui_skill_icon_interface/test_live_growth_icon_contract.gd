extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state := Fixture.earn_offer(sim,21,24)
	var view := View.new().build(state)
	var option: Dictionary = view.active_offer.options[0]
	option.icon_id = "skill_"+str(option.item_id)
	option.requirements = [{"kind":"equipment","item_id":"odm_dash","name":"입체기동 돌진","current":1,"required":1,"met":true,"owned":true,"requirement_type":"owned_skill","icon_id":"skill_odm_dash"}]
	var ui := UI.new()
	t.root.add_child(ui)
	ui.present(sim.snapshot(state))
	ui.present_progression(view)
	for screen in [Vector2i(800,450),Vector2i(450,800),Vector2i(360,800)]:
		ui.reflow(screen,Rect2i(Vector2i.ZERO,screen))
		for frame in range(6): await t.process_frame
		var card: Button = ui._growth_cards[0]
		t.check(card.icon != null,"GameUI summary override preserves actual skill icon at "+str(screen))
		t.check(card.text.contains(str(option.name)) and not ui._subtitle.text.contains("터치/A") and not ui._subtitle.text.contains("i 상세") and not card.text.contains("A · 선택"),"summary override keeps the real name without persistent manipulation instructions")
		var requirements := card.get_node_or_null("Requirements")
		t.check(requirements != null,"growth card owns its small icon+named requirement rows")
		if requirements != null and requirements.get_child_count() > 0:
			var row := requirements.get_child(0)
			t.check(row.get_node("Icon").texture != null and row.get_node("Text").text.contains("입체기동 돌진 · 보유 ✓"),"requirement icon is accompanied by full name and ownership marker")
		card.grab_focus()
		for frame in range(6): await t.process_frame
		t.check(ui._scroll.get_global_rect().grow(1).encloses(card.get_global_rect()),"icon growth choice remains fully visible after controller focus")
	ui.free()
	var path := "res://game/ui/skill_icons.gd"
	t.check(ResourceLoader.exists(path),"shared skill icon helper exists")
	if not ResourceLoader.exists(path): return
	var icons = load(path)
	var silhouettes: Array[PackedByteArray] = []
	for id in ["blade_slash","spin_slash","odm_dash","reentry_combo","wall_cannon","ally_cover","chain_lightning","fire_zone","damage","fire_interval","movement","max_health","recovery","pickup_radius","attack_range","armor","evo_wing_cut","evo_whirlwind","evo_sky_lance","evo_echo_assault","evo_crossfire","evo_wing_squad","evo_storm_chain","evo_inferno_zone"]:
		var texture: Texture2D = icons.texture_for("skill_"+id)
		t.check(texture != null,"distinct skill icon resolves: "+id)
		if texture == null or not id.begins_with("evo_"): continue
		var image := texture.get_image()
		image.resize(32,32,Image.INTERPOLATE_NEAREST)
		var shape := PackedByteArray()
		for y in 32:
			for x in 32:
				var pixel := image.get_pixel(x,y)
				shape.append(1 if pixel.a > 0.5 and maxf(pixel.r,maxf(pixel.g,pixel.b)) > 0.6 else 0)
		t.check(not shape in silhouettes,"evolution has a distinct silhouette instead of only a recolored frame: "+id)
		silhouettes.append(shape)
