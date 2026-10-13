extends RefCounted
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
const Audio = preload("res://game/presentation/audio_director.gd")
const PAIRS := [["spin_slash","evo_whirlwind"],["odm_dash","evo_sky_lance"],["reentry_combo","evo_echo_assault"],["ally_cover","evo_wing_squad"]]
const ALL_PAIRS := [["blade_slash","evo_wing_cut"],["wall_cannon","evo_crossfire"],["chain_lightning","evo_storm_chain"],["fire_zone","evo_inferno_zone"],["spin_slash","evo_whirlwind"],["odm_dash","evo_sky_lance"],["reentry_combo","evo_echo_assault"],["ally_cover","evo_wing_squad"]]
# Removing an evolved recipe, applying the targeted reentry guard to sectors,
# hiding anchorless lines, omitting reduced main shapes, disconnecting profiles
# from real voices, scheduled sounds or damage/replay duplication must fail.
class Capture extends "res://game/presentation/world_view.gd":
	var drawn: Array[Dictionary] = []
	var captured_transform := Transform2D.IDENTITY
	func _world_transform(point: Vector2, angle := 0.0, scale_value := Vector2.ONE) -> void:
		captured_transform = Transform2D(angle,point).scaled_local(scale_value)
	func _world_region(texture: Texture2D, rect: Rect2, region: Rect2, color := Color.WHITE) -> void:
		for id in _textures:
			if str(id).begins_with("vfx_") and _textures[id] == texture:
				drawn.append({"texture":texture,"rect":rect,"region":region,"transform":captured_transform,"color":color})
	func _world_rect(_texture: Texture2D, _rect: Rect2, _tiled: bool, _color := Color.WHITE) -> void: pass
	func capture() -> void:
		drawn.clear()
		_draw()
func run(t) -> void:
	_recipes(t)
	for pair in PAIRS:
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2(0.6,0.8)]:
			_visual_flow(t,pair,direction)
	_reentry_guard(t)
	await _audio_profiles_and_playback(t)
func _recipes(t) -> void:
	var c := Catalog.new()
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	t.check(c.validate(manifest) == ["missing_art:vfx_wire_taut"],"all evolved recipes reuse activated originals without changing approval gates")
	for pair in PAIRS:
		var base: Dictionary = c.recipe(pair[0],"","cast")
		var evo: Dictionary = c.recipe(pair[0],pair[1],"cast")
		t.check(pair[0]+"|"+pair[1] in Catalog.SKILLS,"Catalog enumerates evolved attack "+pair[1])
		t.check(not evo.is_empty(),"evolved cast recipe exists "+pair[1])
		if evo.is_empty(): continue
		t.check(evo.visual_identity != base.visual_identity and evo.layers != base.layers,"evolved morphology has distinct authored raster composition "+pair[1])
		t.check(evo.layers[0].reduce_mode == "preserve","reduced presentation retains evolved contact "+pair[1])
func _visual_flow(t,pair: Array,direction: Vector2) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var bridge := Bridge.new(manifest)
	var view := Capture.new()
	view.load_manifest()
	view._viewport_size = Vector2(1600,900)
	var origin := Vector2(40,70)
	var perpendicular := Vector2(-direction.y,direction.x)
	var stage_geometry: Array[Dictionary] = []
	for stage in 3:
		var geometry := _geometry(pair[1],stage,origin,direction,perpendicular)
		stage_geometry.append(geometry)
		var tick := 10+stage*12
		var event := _attack(stage+1,pair[0],pair[1],stage,tick,geometry)
		var snapshot := _snapshot(tick,stage+1)
		var events: Array[Dictionary] = [event]
		var before := snapshot.duplicate(true)
		var event_before := events.duplicate(true)
		t.check(bridge.consume(events,snapshot),"current executed stage enters successful bridge "+pair[1])
		var commands := bridge.present(snapshot,false)
		var own := commands.filter(func(c): return c.get("attack_id") == event.payload.attack_id)
		t.check(not own.is_empty() and not own.any(func(c): return c.has("diagnostic")),"executed evolution reaches real raster commands without hook anchor "+pair[1])
		var main := own.filter(func(c): return c.get("component") == "main")
		t.check(main.size() == 1,"one mandatory contact main per executed stage "+pair[1])
		if main.size() == 1:
			var m: Dictionary = main[0]
			t.check(m.contact_geometry == geometry and m.world_anchor.is_equal_approx(_vec(geometry.origin)),"evolved raster preserves exact Core stage shape/origin "+pair[1])
			t.check(m.start_tick == tick and m.stage_index == stage,"evolved contact starts on its own execute tick/stage "+pair[1])
			if geometry.shape == "line":
				t.check(m.contact_size == Vector2(geometry.length,geometry.width) and is_equal_approx(m.rotation,_vec(geometry.direction).angle()),"forward/crossing line retains exact length width direction "+pair[1])
				var asset: Dictionary = manifest.assets[m.asset_id]
				var b: Array = asset.vfx_bounds_px
				var local_first: Vector2 = Vector2(b[0],b[1])+m.local_rect.position
				var local_end: Vector2 = local_first+Vector2(b[2],b[3])
				var first: Vector2 = m.world_anchor+(local_first*m.scale).rotated(m.rotation)
				var end: Vector2 = m.world_anchor+(local_end*m.scale).rotated(m.rotation)
				var axis := _vec(geometry.direction).normalized()
				var normal := Vector2(-axis.y,axis.x)
				t.check(first.is_equal_approx(_vec(geometry.origin)-normal*geometry.width*0.5) and end.is_equal_approx(_vec(geometry.origin)+axis*geometry.length+normal*geometry.width*0.5),"actual raster contact bounds start at Core line origin and end at endpoint "+pair[1])
			else:
				t.check(m.contact_size == Vector2.ONE*float(geometry.radius)*2.0,"circle/sector keeps actual radius "+pair[1])
			if geometry.shape == "sector":
				t.check(is_equal_approx(m.rotation,_vec(geometry.direction).angle()),"echo rotates with alternating Core sectors")
		var reduced := bridge.present(snapshot,true).filter(func(c): return c.get("attack_id") == event.payload.attack_id)
		t.check(reduced.any(func(c): return c.get("component") == "main") and not reduced.any(func(c): return c.has("diagnostic")),"reduced VFX retains exact evolved actual-contact main "+pair[1])
		bridge.consume(events,snapshot)
		t.check(bridge.present(snapshot,false) == commands,"duplicate successful stage cannot duplicate VFX "+pair[1])
		view.consume_combat_events(events,snapshot)
		view.present(snapshot)
		var actual: Array = view.combat_vfx_commands()
		view.capture()
		var valid := actual.filter(func(c): return not c.has("diagnostic"))
		t.check(view.drawn.size() == valid.size() and not valid.is_empty(),"WorldView emits every evolved raster draw "+pair[1])
		for command in valid:
			var matches := view.drawn.filter(func(d): return d.region == command.atlas_region and d.rect == command.local_rect and d.transform.origin.is_equal_approx(view._screen(command.world_anchor)))
			t.check(not matches.is_empty(),"actual draw uses authored atlas region and frozen Core anchor "+pair[1])
		t.check(snapshot == before and events == event_before,"presentation never edits Core geometry/events "+pair[1])
		t.check(own.size() <= 3,"evolved contact raster cost bounded to three layers "+pair[1])
	t.check(stage_geometry[0] != stage_geometry[1] and stage_geometry[1] != stage_geometry[2],"three stages retain different actual trajectory geometry "+pair[1])
	view.free()
func _reentry_guard(t) -> void:
	var d := Director.new()
	var geometry := {"shape":"targeted","origin":[40,70],"direction":[1,0],"radius":80,"target_id":2}
	var miss := _attack(1,"reentry_combo","",0,10,geometry)
	d.consume(_events([miss]),_snapshot(10,1))
	t.check(d.present(_snapshot(10,1)).is_empty(),"basic reentry still cannot claim a successful triple on miss")
	var unique := _attack(2,"character:mikasa_unique_attack","",0,11,{"shape":"sector","origin":[40,70],"direction":[1,0],"radius":54,"arc_degrees":150})
	d.consume(_events([unique]),_snapshot(11,2))
	t.check(d.present(_snapshot(11,2)).any(func(e): return e.get("base_item_id") == "character:mikasa_unique_attack"),"character-specific attack presentation remains independent")
func _audio_profiles_and_playback(t) -> void:
	var a := Audio.new()
	t.root.add_child(a)
	await t.process_frame
	t.check(a._voices.size() == 8,"audio retains bounded eight-voice pool")
	t.check(a.has_method("sound_profile_for_event"),"audio exposes executed evolution profiles consumed by real voices")
	if not a.has_method("sound_profile_for_event"):
		a.free()
		return
	var identities: Array[String] = []
	for index in ALL_PAIRS.size():
		var pair: Array = ALL_PAIRS[index]
		var e := _attack(index+1,pair[0],pair[1],0,10,{"shape":"circle","origin":[40,70],"direction":[1,0],"radius":84})
		var before := e.duplicate(true)
		var profile: Dictionary = a.sound_profile_for_event(e)
		t.check(not profile.is_empty(),"every ultimate has an executed sound profile "+pair[1])
		if profile.is_empty(): continue
		identities.append(str([profile.id,profile.pitch_scale,profile.volume_db]))
		var later := e.duplicate(true); later.payload.stage_index = 1
		var next_profile: Dictionary = a.sound_profile_for_event(later)
		t.check(next_profile != profile,"sound follows executed evolution stage "+pair[1])
		var scheduled := e.duplicate(true); scheduled.payload.phase = "scheduled"
		t.check(a.sound_profile_for_event(scheduled).is_empty() and a.sound_for_event(scheduled).is_empty(),"scheduled evolution never sounds before contact "+pair[1])
		a.reset_presentation()
		a.consume_events(_events([scheduled]))
		t.check(not a._voices.any(func(v): return v.playing),"scheduled event does not actually start a voice "+pair[1])
		a.reset_presentation()
		var damage := {"event_id":"run:"+str(index+20),"type":"damage","tick":10,"payload":{"attack_id":e.payload.attack_id,"source_id":pair[0],"target_id":2,"amount":10,"position":[40,70]}}
		a.consume_events(_events([damage,e]))
		var active := a._voices.filter(func(v): return v.playing)
		t.check(active.size() == 1,"evolved contact and many-target damage produce one stage voice "+pair[1])
		if active.size() == 1:
			t.check(active[0].stream == a._stream(profile.id) and is_equal_approx(active[0].pitch_scale,profile.pitch_scale) and is_equal_approx(active[0].volume_db,profile.volume_db),"actual AudioStreamPlayer uses evolved asset/pitch/volume "+pair[1])
		t.check(e == before,"sound profile never mutates combat event")
		a.reset_presentation()
	t.check(identities.size() == 8 and _unique(identities).size() == 8,"all eight ultimates have distinguishable actual sound signatures")
	var basic := _attack(1,"blade_slash","",0,10,{"shape":"sector","origin":[0,0],"direction":[1,0],"radius":54})
	var hit := {"event_id":"run:2","type":"damage","tick":10,"payload":{"attack_id":basic.payload.attack_id,"source_id":"blade_slash","target_id":2,"amount":10}}
	a.consume_events(_events([basic,hit]))
	t.check(a._voices.filter(func(v): return v.playing and v.stream == a._stream("slash")).size() == 1,"basic damage sound is never suppressed by basic executed event")
	a.reset_presentation()
	var evolved := _attack(1,"spin_slash","evo_whirlwind",0,10,{"shape":"circle","origin":[0,0],"direction":[1,0],"radius":80})
	a.consume_events(_events([evolved]))
	await t.create_timer(0.09).timeout
	for v in a._voices: v.stop()
	a.consume_events(_events([evolved]))
	t.check(not a._voices.any(func(v): return v.playing),"replayed evolved event remains silent after seventy-ms cooldown")
	a.reset_presentation()
	a.consume_events(_events([evolved]))
	t.check(a._voices.filter(func(v): return v.playing).size() == 1,"new presentation run can replay identical tick with fresh voice")
	a.reset_presentation()
	var catch_up: Array[Dictionary] = []
	for stage in 3:
		var e := evolved.duplicate(true)
		e.event_id = "run:"+str(stage+1)
		e.tick = 10+stage*12
		e.payload.execute_tick = e.tick
		e.payload.stage_index = stage
		e.payload.attack_id = "run:attack:1:"+str(stage)
		catch_up.append(e)
	a.consume_events(catch_up)
	var stage_voices := a._voices.filter(func(v): return v.playing)
	t.check(stage_voices.size() == 3,"three already-executed catch-up stages retain three bounded voices")
	for event in catch_up:
		var profile: Dictionary = a.sound_profile_for_event(event)
		t.check(stage_voices.any(func(v): return is_equal_approx(v.pitch_scale,profile.pitch_scale)),"catch-up voice carries its real executed stage pitch")
	a.reset_presentation()
	var evolution_data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/evolutions.json"))
	var inferno_params: Dictionary = evolution_data.items.evo_inferno_zone.effect_params
	var final_stage: int = inferno_params.stage_delays.size()-1
	var inferno_first := _attack(1,"fire_zone","evo_inferno_zone",1,10+int(inferno_params.stage_delays[1]),{"shape":"circle","origin":[0,0],"direction":[1,0],"radius":inferno_params.radius})
	inferno_first.payload.stage_count = inferno_params.stage_delays.size()
	var inferno_final := inferno_first.duplicate(true)
	inferno_final.event_id = "run:2"
	inferno_final.tick = 10+int(inferno_params.stage_delays[final_stage])
	inferno_final.payload.execute_tick = inferno_final.tick
	inferno_final.payload.stage_index = final_stage
	inferno_final.payload.attack_id = "run:attack:1:"+str(final_stage)
	inferno_final.payload.geometry.radius = inferno_params.eruption_radius
	a.consume_events(_events([inferno_first,inferno_final]))
	var eruption_profile: Dictionary = a.sound_profile_for_event(inferno_final)
	t.check(final_stage == 7 and 1%3 == final_stage%3,"authored inferno pulse1/final7 share the bounded modulo bucket")
	t.check(eruption_profile.id == "cannon" and a._voices.filter(func(v): return v.playing).size() == 2,"catch-up authored inferno preserves a separate final eruption voice")
	t.check(a._voices.any(func(v): return v.playing and v.stream == a._stream("cannon") and is_equal_approx(v.pitch_scale,eruption_profile.pitch_scale)),"final inferno stage actually plays its eruption stream and pitch")
	a.reset_presentation()
	var burst: Array[Dictionary] = []
	for index in 120:
		var e := evolved.duplicate(true)
		e.event_id = "run:"+str(index+1)
		e.payload.attack_id = "run:attack:"+str(index)+":0"
		burst.append(e)
	a.consume_events(burst)
	t.check(a._voices.size() == 8 and a._voices.filter(func(v): return v.playing).size() <= 8,"burst cannot expand eight-voice pool")
	a.free()
func _snapshot(tick: int,seq: int) -> Dictionary:
	return {"run_id":"run","seed":1,"active_tick":tick,"event_seq":seq,"origin_revision":0,"phase":"survival","pause_reasons":[],"player":{"position":[40,70],"facing":[1,0],"velocity":[0,0]},"entities":[],"projectiles":[],"player_attack_instances":[]}
func _attack(seq: int,base: String,evo: String,stage: int,tick: int,geometry: Dictionary) -> Dictionary:
	return {"event_id":"run:"+str(seq),"type":"player_attack","tick":tick,"payload":{"cast_id":"run:attack:1","attack_id":"run:attack:1:"+str(stage),"base_item_id":base,"evolution_id":evo,"stage_index":stage,"stage_count":3,"phase":"executed","execute_tick":tick,"origin":geometry.origin,"direction":geometry.direction,"geometry":geometry}}
func _geometry(evo: String,stage: int,origin: Vector2,direction: Vector2,perpendicular: Vector2) -> Dictionary:
	var point := origin
	var axis := direction
	match evo:
		"evo_whirlwind": return {"shape":"circle","origin":_arr(origin+Vector2(stage*3,stage*2)),"direction":_arr(direction),"radius":[80.0,106.0,132.0][stage]}
		"evo_sky_lance": point += direction*[0.0,72.0,144.0][stage]
		"evo_echo_assault":
			point += perpendicular*[-30.0,30.0,0.0][stage]
			axis = direction.rotated(deg_to_rad([45.0,-45.0,0.0][stage]))
			return {"shape":"sector","origin":_arr(point),"direction":_arr(axis),"radius":84.0,"arc_degrees":125.0}
		"evo_wing_squad":
			point += perpendicular*[-28.0,28.0,0.0][stage]+direction*(28.0 if stage == 2 else 0.0)
			axis = direction.rotated(deg_to_rad([24.0,-24.0,0.0][stage]))
	return {"shape":"line","origin":_arr(point),"direction":_arr(axis),"radius":0.0,"length":104.0 if evo == "evo_sky_lance" else 320.0,"width":32.0 if evo == "evo_sky_lance" else 24.0}
func _events(values: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in values: output.append(value)
	return output
func _vec(v: Array) -> Vector2: return Vector2(v[0],v[1])
func _arr(v: Vector2) -> Array: return [v.x,v.y]
func _unique(values: Array) -> Array:
	var output := []
	for v in values:
		if not v in output: output.append(v)
	return output
