extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const UI = preload("res://game/ui/game_ui.gd")
const View = preload("res://game/progression/progression_view.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const VfxCatalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Signature = preload("res://game/combat/character_skill_resolver.gd")
func run(t) -> void:
	var sim = F.simulation(t)
	var config := F.run_config()
	config.character_id = "mikasa_01"
	config.character_skill_revision = 1
	var state: Dictionary = sim.new_run(F.chapter(),31,config)
	state.player.attack_ready_ticks.blade_slash = 10000
	var ui = UI.new()
	t.root.add_child(ui)
	ui.present(state)
	ui.present_progression(View.new().build(state))
	var hud = ui.get_node("ProgressionHUD")
	var label = hud.get_node_or_null("CharacterSkill")
	t.check(label != null,"dedicated read-only signature HUD exists")
	if label == null: ui.free(); return
	t.check(label.text == "고유 · 집중 연격 · 준비" and label.mouse_filter == Control.MOUSE_FILTER_IGNORE,"ready signature line ignores pointer input")
	var revision: int = state.view_revision
	var slots := []
	for slot in hud.slot_controls(): slots.append(slot.get_instance_id())
	var vfx := Director.new()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var bridge := Bridge.new(manifest)
	var raster_ticks := []
	var execution_ticks := []
	var hit_feedback := []
	var first: Array[Dictionary] = []
	for index in 17:
		var events := F.step(sim,state,Vector2.ZERO,[F.spawn("vfx-target",[65,0],"brute")] if index == 0 else [])
		if index == 0: first = events
		t.check(bridge.consume(events,state),"actual VFX bridge accepts successful signature tick")
		var raster_commands: Array[Dictionary] = bridge.present(state)
		t.check(not raster_commands.any(func(c): return c.has("diagnostic")),"approved raster bytes render without diagnostics")
		for command in raster_commands:
			if command.get("base_item_id") == Signature.TOKEN and command.start_tick == state.active_tick:
				raster_ticks.append(int(state.active_tick))
				t.check(command.asset_id == "vfx_blade_crescent" and command.contact_geometry.radius == 96.0,"actual renderer preserves approved art and real attack radius")
		if index == 0:
			var cold := Bridge.new(manifest)
			t.check(cold.present(state).is_empty(),"cold presentation does not replay prior slash or hit spark from pending records")
		vfx.consume(events,state)
		var effects: Array[Dictionary] = vfx.present(state)
		for effect in effects:
			if effect.get("base_item_id") == Signature.TOKEN and effect.start_tick == state.active_tick:
				execution_ticks.append(int(state.active_tick))
				t.check(effect.end_tick-effect.start_tick <= 8 and effect.geometry.radius == 96.0 and not effect.geometry.has("target_id"),"short real-range blade effect without target scan")
			if effect.get("role") == "impact" and effect.start_tick == state.active_tick: hit_feedback.append(int(state.active_tick))
		ui.present(state)
		if index == 0: t.check(label.text.ends_with("연격 중"),"HUD reports pending 3-strike cast")
	t.check(raster_ticks == [1,9,17],"three actual raster draw commands occur only on real execution ticks")
	t.check(execution_ticks == [1,9,17],"each real executed strike makes exactly one blade VFX")
	t.check(hit_feedback == [1,9,17],"each real hit creates its ordinary damage feedback")
	t.check(state.view_revision == revision and label.text.ends_with("11.8초"),"live cooldown updates while progression revision remains unchanged")
	vfx.consume(first,state)
	t.check(vfx.present(state).size() <= 2,"replayed event batch does not duplicate VFX")
	for screen in [Vector2i(320,568),Vector2i(640,360),Vector2i(450,800),Vector2i(800,450)]:
		var safe := Rect2i(12,8,screen.x-24,screen.y-16)
		ui.reflow(screen,safe)
		for frame in 3: await t.process_frame
		t.check(Rect2(safe).encloses(hud.get_global_rect()) and hud.get_global_rect().encloses(label.get_global_rect()),"signature line is inside safe HUD "+str(screen))
		t.check(label.size.y >= label.get_minimum_size().y and label.size.x >= label.get_minimum_size().x,"signature text is not clipped "+str(screen))
		t.check(not label.get_global_rect().intersects(ui._objective.get_global_rect()),"signature does not overlap objective "+str(screen))
		t.check(hud.slot_controls().size() == 8,"signature consumes no loadout slot")
	for i in 8: t.check(slots[i] == hud.slot_controls()[i].get_instance_id(),"signature ticking preserves existing fixed controls")
	var before: String = label.text
	sim.set_pause(state,"user",true)
	for i in 12: F.step(sim,state,Vector2.ZERO); ui.present(state)
	t.check(label.text == before,"pause freezes HUD cooldown")
	ui.open_owned_skills()
	t.check(ui._mode == "owned_skills" and ui._choices.get_children().any(func(c): return c is Label and c.text.contains("집중 연격") and c.text.contains("대표 궁극 미구현")),"existing owned details explains real signature and planned ultimate")
	ui.open_owned_skills()
	ui.close_owned_skills()
	t.check(not ui._owned_open and ui._mode == "pause" and label.text == before,"repeated detail open and close preserve paused cooldown and input mode")
	state.character_skill.ready_tick = state.active_tick
	state.character_skill.next_probe_tick = state.active_tick
	ui.present(state)
	t.check(label.text.ends_with("준비"),"elapsed cooldown returns to ready")
	state.run_config.erase("character_skill_revision")
	state.erase("character_skill")
	ui.present(state)
	t.check(label.text == "고유 공격 · 다음 출격부터","legacy selected run has truthful transition copy")
	state.character_id = "garrison_01"
	ui.present(state)
	t.check(not label.visible and hud.size.y == 108,"non-signature character retains original HUD layout")
	ui.free()
	var recipe := VfxCatalog.new().recipe(Signature.TOKEN,"","cast")
	t.check(recipe.get("art_id") == "vfx_blade_crescent" and recipe.get("duration_ticks") == 8,"signature reuses original approved blade art for eight ticks")
