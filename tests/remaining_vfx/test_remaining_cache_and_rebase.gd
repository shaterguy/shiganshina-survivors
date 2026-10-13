extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Renderer = preload("res://game/presentation/combat_vfx_renderer.gd")
const IDS := ["vfx_dash_compressed_gas","vfx_dash_cross_tip","vfx_reentry_triple","vfx_ally_gas_swoop","vfx_ally_arrival_cut"]
class CountingBridge:
	extends Bridge
	var reads: Dictionary = {}
	func _raster_problem(id: String) -> String:
		if not _raster_validation.has(id): reads[id] = int(reads.get(id,0))+1
		return super._raster_problem(id)
func run(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	state.equipment = {"odm_dash":1,"reentry_combo":1,"ally_cover":1}
	var bridge := CountingBridge.new(manifest); var seen := {}; var max_commands := 0
	var wire_core_skills: Dictionary = {}; var wire_effect_count := 0; var wire_geometry_fields: Dictionary = {}
	for tick in 20:
		var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("cache-target",[60,0],"brute")] if tick == 0 else [])
		state.player.attack_ready_ticks = {"odm_dash":999999,"reentry_combo":999999,"ally_cover":999999}
		var snapshot: Dictionary = sim.snapshot(state)
		var snapshot_bytes: PackedByteArray = var_to_bytes(snapshot)
		var event_bytes: PackedByteArray = var_to_bytes(events)
		for event in events:
			var payload: Dictionary = event.get("payload",{})
			if event.get("type") != "player_attack" or payload.get("phase") != "executed" or payload.get("base_item_id") not in ["odm_dash","ally_cover"]: continue
			wire_core_skills[payload.base_item_id] = true
			var geometry: Dictionary = payload.get("geometry",{})
			wire_geometry_fields[payload.base_item_id] = geometry.keys()
			t.check(not geometry.has("target_id") and not geometry.has("wire_anchor"),"ordinary actual Core dash/ally event does not invent a wire target")
		t.check(bridge.consume(events,snapshot),"mixed actual Core batch accepted")
		var drawn := bridge.present(snapshot)
		for effect in bridge._director.present(snapshot):
			if effect.get("base_item_id") not in ["odm_dash","ally_cover"]: continue
			wire_effect_count += 1
			t.check(not effect.geometry.has("target_id") and not effect.geometry.has("wire_anchor"),"actual director dash/ally effect keeps the absent wire anchor absent")
		t.check(not drawn.any(func(c): return c.get("asset_id") == "vfx_wire_taut"),"ordinary actual Core pipeline never requests an unanchored wire raster or its diagnostic")
		max_commands = maxi(max_commands,drawn.size())
		t.check(drawn.filter(func(c): return c.get("asset_id") in IDS).size() <= 4,"mixed skills never duplicate mandatory layers")
		t.check(drawn.filter(func(c): return c.get("asset_id") == "vfx_hit_spark").size() <= 2,"launch contacts and later arrival own at most two overlapping spark recoveries")
		for command in drawn:
			t.check(not command.has("diagnostic"),"mixed remaining skills resolve all required rasters")
			if not command.has("diagnostic"): seen[command.asset_id] = true
		var read_count: Dictionary = bridge.reads.duplicate()
		for repeat_index in 8: t.check(bridge.present(snapshot) == drawn,"unchanged render has stable deterministic commands")
		t.check(bridge.reads == read_count,"repeat presents never rehash or decode original raster")
		var reduced := bridge.present(snapshot,true)
		for id in IDS:
			t.check(reduced.filter(func(c): return c.get("asset_id") == id).size() == drawn.filter(func(c): return c.get("asset_id") == id).size(),"reduced effects keeps mandatory skill shape: "+id)
		if tick == 0: _rebase(t,manifest,events,snapshot)
		t.check(var_to_bytes(snapshot) == snapshot_bytes and var_to_bytes(sim.snapshot(state)) == snapshot_bytes and var_to_bytes(events) == event_bytes,"normal wire residual observation leaves full Core snapshot and events byte-exact")
	t.check(wire_core_skills.has_all(["odm_dash","ally_cover"]) and wire_effect_count > 0,"wire residual observation reaches both genuine Core casts and live director effects")
	var catalog = load("res://game/presentation/combat_vfx_catalog.gd").new()
	var inputs: Dictionary = {}
	for path in ["assets/manifest.json","data/combat_vfx.json","data/equipment.json","data/evolutions.json","game/combat/evolved_attack_resolver.gd","game/progression/evolution_catalog.gd","game/core/run_simulation.gd","game/presentation/combat_vfx_director.gd","game/presentation/combat_vfx_renderer.gd","game/presentation/combat_vfx_bridge.gd"]:
		inputs[path] = FileAccess.get_sha256("res://"+path)
	print("VFX_WIRE_RESIDUAL_OBSERVATION ",JSON.stringify({"actual_Core_skills":wire_core_skills.keys(),"actual_event_geometry_fields":wire_geometry_fields,"observed_director_effects":wire_effect_count,"actual_manifest_has_wire":manifest.assets.has("vfx_wire_taut"),"actual_catalog_validation":catalog.validate(manifest),"other_actual_rasters_seen":seen.keys(),"input_sha256":inputs,"scope":"normal current Core casts only; no invented anchor; residual catalog diagnostic is preserved, not art approval"},"",true,true))
	t.check(seen.has_all(IDS),"mixed actual Core flow reaches all five rasters")
	t.check(bridge.reads.size() == 6 and bridge.reads.values().all(func(count): return count == 1),"five originals plus hit spark each validate once per immutable configuration")
	t.check(max_commands <= 6,"three simultaneous casts stay within four skill layers plus two separately timed hit sparks")
	print("REMAINING_VFX_COST original_validations=",bridge.reads," mixed_peak_commands=",max_commands," unchanged_present_repeats=160")
	_evolved_wire_observation(t,manifest)
func _rebase(t,manifest: Dictionary,events: Array[Dictionary],snapshot: Dictionary) -> void:
	var director := Director.new(); director.consume(events,snapshot)
	var renderer := Renderer.new()
	var initial := renderer.commands(director.present(snapshot),{"tick":snapshot.active_tick,"origin_revision":0,"asset_metadata":manifest})
	var before := initial.filter(func(c): return c.get("asset_id") == "vfx_reentry_triple")
	t.check(before.size() == 1,"actual reentry contact is available for presentation-only rebase")
	if before.size() != 1: return
	var shifted := snapshot.duplicate(true); var offset := Vector2(768,0)
	shifted.origin_revision = 1
	shifted.player.position[0] -= offset.x
	for entity in shifted.entities: entity.position[0] -= offset.x
	for projectile in shifted.projectiles: projectile.position[0] -= offset.x
	director.rebase(offset,1)
	var after := renderer.commands(director.present(shifted),{"tick":snapshot.active_tick,"origin_revision":1,"asset_metadata":manifest}).filter(func(c): return c.get("asset_id") == "vfx_reentry_triple")
	t.check(after.size() == 1 and after[0].world_anchor.is_equal_approx(before[0].world_anchor-offset),"frozen successful contact rebases exactly once")
	if after.size() == 1:
		t.check(after[0].contact_size == Vector2(36,36) and after[0].contact_geometry.radius == 80.0,"rebase preserves separate visual footprint and unchanged Core range")
	director.rebase(offset,1)
	var duplicate := renderer.commands(director.present(shifted),{"tick":snapshot.active_tick,"origin_revision":1,"asset_metadata":manifest}).filter(func(c): return c.get("asset_id") == "vfx_reentry_triple")
	t.check(after == duplicate,"same origin revision cannot shift successful contact twice")

# Version-scoped observation, not a rule against future anchored wire artwork.
func _evolved_wire_observation(t, manifest: Dictionary) -> void:
	var catalog = load("res://game/progression/upgrade_catalog.gd").new()
	for id in ["evo_sky_lance","evo_wing_squad"]:
		var recipe: Dictionary = catalog.evolutions.definition(id)
		var sim = F.simulation(t)
		var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
		state.equipment = {recipe.base_item_id:5}
		for required in recipe.get("required_equipment",[]): state.equipment[required.equipment_id] = int(required.level)
		for required in recipe.required_passives: state.passives[required.passive_id] = int(required.level)
		for base in state.equipment: state.player.attack_ready_ticks[base] = 2147483647
		t.check(sim.restore(state).get("ok",false),"wire observation uses a valid final-ready current Core state: "+id)
		F.drop_xp(sim,state,24,"wire:xp:"+id)
		var chosen: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.get("offer_id",""),"evolution:"+id)
		t.check(chosen.get("ok",false) and state.evolutions.get(recipe.base_item_id) == id,"wire observation selects real final evolution through current XP offer: "+id)
		if not chosen.get("ok",false): continue
		state.player.attack_ready_ticks[recipe.base_item_id] = state.active_tick
		var bridge := Bridge.new(manifest)
		var stages: Dictionary = {}; var effect_stages: Dictionary = {}; var art: Dictionary = {}; var geometry_fields: Dictionary = {}
		for tick in 30:
			var position: Array = [float(state.player.position[0])+60.0,float(state.player.position[1])]
			var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("wire:target:"+id,position,"brute")] if tick == 0 else [])
			state.player.attack_ready_ticks[recipe.base_item_id] = 2147483647
			var snapshot: Dictionary = sim.snapshot(state)
			var frozen: PackedByteArray = var_to_bytes(snapshot); var frozen_events: PackedByteArray = var_to_bytes(events)
			for event in events:
				var payload: Dictionary = event.get("payload",{})
				if event.get("type") != "player_attack" or payload.get("phase") != "executed" or payload.get("evolution_id") != id: continue
				stages[int(payload.stage_index)] = true
				var geometry: Dictionary = payload.get("geometry",{}); geometry_fields[str(payload.stage_index)] = geometry.keys()
				t.check(not geometry.has("target_id") and not geometry.has("wire_anchor"),"current final-stage Core event has no explicit wire target: "+id)
			t.check(bridge.consume(events,snapshot),"actual final-stage event batch reaches presentation: "+id)
			var commands := bridge.present(snapshot)
			for effect in bridge._director.present(snapshot):
				if effect.get("evolution_id") != id: continue
				effect_stages[int(effect.stage_index)] = true
				t.check(not effect.geometry.has("target_id") and not effect.geometry.has("wire_anchor"),"current final-stage director effect has no explicit wire anchor: "+id)
			for command in commands:
				t.check(not command.has("diagnostic") and command.get("asset_id") != "vfx_wire_taut","current final-stage raster path has no missing-art or wire request: "+id)
				if not command.has("diagnostic"): art[command.asset_id] = true
			t.check(var_to_bytes(snapshot) == frozen and var_to_bytes(sim.snapshot(state)) == frozen and var_to_bytes(events) == frozen_events,"final-stage observation leaves full Core snapshot and events byte-exact: "+id)
		t.check(stages.has_all([0,1,2]) and stages.size() == 3 and effect_stages.has_all([0,1,2]),"wire observation reaches all three genuine final attack and director stages: "+id)
		var expected: Array = ["vfx_chain_lightning","vfx_dash_cross_tip"] if id == "evo_sky_lance" else ["vfx_ally_gas_swoop","vfx_ally_arrival_cut"]
		t.check(art.has_all(expected),"actual final-stage mandatory visible art remains present: "+id)
		print("VFX_WIRE_EVOLVED_OBSERVATION ",JSON.stringify({"evolution_id":id,"base_item_id":recipe.base_item_id,"executed_stages":stages.keys(),"director_stages":effect_stages.keys(),"geometry_fields":geometry_fields,"actual_rasters":art.keys(),"scope":"current selected final recipe and actual Core stages only; no future wire restriction"},"",true,true))
