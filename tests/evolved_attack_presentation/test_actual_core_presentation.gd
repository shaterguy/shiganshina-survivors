extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Upgrades = preload("res://game/progression/upgrade_catalog.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
const Audio = preload("res://game/presentation/audio_director.gd")
const PAIRS := [["spin_slash","evo_whirlwind"],["odm_dash","evo_sky_lance"],["reentry_combo","evo_echo_assault"],["ally_cover","evo_wing_squad"]]
# A real XP choice must flow through actual Core reserve/resolve events, then
# the successful snapshot adapter, raster draw and bounded actual sound voices.
class Capture extends "res://game/presentation/world_view.gd":
	var rasters: Array[Dictionary] = []
	var captured_transform := Transform2D.IDENTITY
	func _world_transform(point: Vector2, angle := 0.0, scale_value := Vector2.ONE) -> void:
		captured_transform = Transform2D(angle,point).scaled_local(scale_value)
	func _world_region(texture: Texture2D, rect: Rect2, region: Rect2, color := Color.WHITE) -> void:
		for id in _textures:
			if str(id).begins_with("vfx_") and _textures[id] == texture:
				rasters.append({"asset_id":id,"rect":rect,"region":region,"transform":captured_transform,"color":color})
	func _world_rect(_texture: Texture2D, _rect: Rect2, _tiled: bool, _color := Color.WHITE) -> void: pass
	func capture() -> void:
		rasters.clear()
		_draw()
func run(t) -> void:
	for pair in PAIRS: await _actual_flow(t,pair)
func _actual_flow(t,pair: Array) -> void:
	var catalog := Upgrades.new()
	var recipe: Dictionary = catalog.evolutions.definition(pair[1])
	t.check(not recipe.is_empty(),"actual Core presentation has selected final recipe "+pair[1])
	if recipe.is_empty(): return
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),77,F.run_config())
	t.check(not state.has("error_code"),"actual presentation constructs valid current Core "+pair[1])
	if state.has("error_code"): return
	state.equipment = {pair[0]:5}
	state.passives = {}
	for required in recipe.get("required_equipment",[]): state.equipment[str(required.equipment_id)] = int(required.level)
	for required in recipe.get("required_passives",[]): state.passives[str(required.passive_id)] = int(required.level)
	for base in state.equipment: state.player.attack_ready_ticks[base] = 2147483647
	F.drop_xp(sim,state,24,"actual:vfx:xp:"+pair[1])
	var choice: Dictionary = sim.choose_upgrade(state,str(state.upgrade_offer.get("offer_id","")),"evolution:"+pair[1])
	t.check(choice.get("ok",false),"real XP offer selects evolution before actual presentation "+pair[1])
	if not choice.get("ok",false): return
	state.player.attack_ready_ticks[pair[0]] = int(state.active_tick)
	var point := Vector2(state.player.position[0],state.player.position[1])+Vector2(60,0)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var bridge := Bridge.new(manifest)
	var view := Capture.new()
	view.load_manifest()
	view._viewport_size = Vector2(1600,900)
	var audio := Audio.new()
	t.root.add_child(audio)
	await t.process_frame
	var executed: Array[Dictionary] = []
	var stages: Array[int] = []
	var planned: Array[int] = []
	var initial_geometry: Dictionary = {}
	for index in 34:
		var events: Array[Dictionary] = F.step(sim,state,Vector2.RIGHT,[F.spawn("actual:vfx:target:"+pair[1],[point.x,point.y],"brute")] if index == 0 else [])
		state.player.attack_ready_ticks[pair[0]] = 2147483647
		var snapshot: Dictionary = sim.snapshot(state)
		var before := snapshot.duplicate(true)
		var events_before := events.duplicate(true)
		t.check(bridge.consume(events,snapshot),"actual Core batch binds exact successful tick "+pair[1])
		view.consume_combat_events(events,snapshot)
		view.present(snapshot)
		var commands := bridge.present(snapshot,false)
		var reduced := bridge.present(snapshot,true)
		var drawn_commands: Array[Dictionary] = view.combat_vfx_commands()
		view.capture()
		for event in events:
			if event.type != "player_attack" or event.payload.base_item_id != pair[0]: continue
			var own := commands.filter(func(c): return c.get("attack_id") == event.payload.attack_id)
			if event.payload.phase == "scheduled":
				planned.append(int(event.payload.stage_index))
				if int(event.payload.execute_tick) > int(snapshot.active_tick):
					t.check(own.is_empty(),"real pending stage cannot render a premature attack "+pair[1])
				t.check(audio.sound_for_event(event).is_empty(),"real pending stage cannot sound early "+pair[1])
				continue
			if event.payload.phase != "executed": continue
			executed.append(event.duplicate(true))
			stages.append(int(event.payload.stage_index))
			if initial_geometry.is_empty(): initial_geometry = event.payload.geometry.duplicate(true)
			var main := own.filter(func(c): return c.get("component") == "main")
			t.check(main.size() == 1 and not own.any(func(c): return c.has("diagnostic")),"actual Core evolution produces one valid contact main "+pair[1])
			if main.size() != 1: continue
			var m: Dictionary = main[0]
			t.check(m.contact_geometry == event.payload.geometry and m.world_anchor.is_equal_approx(Vector2(event.payload.origin[0],event.payload.origin[1])),"real frozen stage geometry reaches renderer without reconstruction "+pair[1])
			t.check(m.start_tick == event.tick and m.stage_index == event.payload.stage_index,"real stage tick and index reach renderer "+pair[1])
			t.check(reduced.any(func(c): return c.get("attack_id") == event.payload.attack_id and c.get("component") == "main"),"real reduced VFX keeps actual strike main "+pair[1])
			var actual := drawn_commands.filter(func(c): return c.get("attack_id") == event.payload.attack_id and c.get("component") == "main")
			t.check(actual.size() == 1 and view.rasters.any(func(r): return r.asset_id == m.asset_id and r.region == m.atlas_region and r.transform.origin.is_equal_approx(view._screen(m.world_anchor))),"real Core main reaches WorldView raster draw "+pair[1])
		bridge.consume(events,snapshot)
		t.check(bridge.present(snapshot,false) == commands,"real batch replay never duplicates contacts "+pair[1])
		t.check(snapshot == before and events == events_before,"actual presentation leaves Core state/event bytes unchanged "+pair[1])
	t.check(stages == [0,1,2] and planned == [0,1,2],"real reserve and execute produce exactly three authored stages "+pair[1])
	t.check(state.player_attack_instances.is_empty(),"actual delayed stages retire before presentation finish "+pair[1])
	if executed.size() == 3:
		t.check(executed[1].payload.geometry != initial_geometry and executed[2].payload.geometry != initial_geometry,"real stage trajectories differ from first stage "+pair[1])
		if pair[1] == "evo_echo_assault":
			var first: Array = executed[0].payload.direction
			var second: Array = executed[1].payload.direction
			t.check(first[1] > 0 and second[1] < 0,"actual echo side sectors aim toward central target")
		audio.reset_presentation()
		audio.consume_events(executed)
		var voices := audio._voices.filter(func(v): return v.playing)
		t.check(audio._voices.size() == 8 and voices.size() == 3,"actual Core catch-up executes three distinct bounded sound voices "+pair[1])
		if audio.has_method("sound_profile_for_event"):
			for event in executed:
				var profile: Dictionary = audio.sound_profile_for_event(event)
				t.check(voices.any(func(v): return v.stream == audio._stream(profile.id) and is_equal_approx(v.pitch_scale,profile.pitch_scale) and is_equal_approx(v.volume_db,profile.volume_db)),"actual Core stage drives real evolved voice asset/pitch/volume "+pair[1])
	view.free()
	audio.free()
