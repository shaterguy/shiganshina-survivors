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
	for tick in 20:
		var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("cache-target",[60,0],"brute")] if tick == 0 else [])
		state.player.attack_ready_ticks = {"odm_dash":999999,"reentry_combo":999999,"ally_cover":999999}
		var snapshot: Dictionary = sim.snapshot(state)
		t.check(bridge.consume(events,snapshot),"mixed actual Core batch accepted")
		var drawn := bridge.present(snapshot)
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
	t.check(seen.has_all(IDS),"mixed actual Core flow reaches all five rasters")
	t.check(bridge.reads.size() == 6 and bridge.reads.values().all(func(count): return count == 1),"five originals plus hit spark each validate once per immutable configuration")
	t.check(max_commands <= 6,"three simultaneous casts stay within four skill layers plus two separately timed hit sparks")
	print("REMAINING_VFX_COST original_validations=",bridge.reads," mixed_peak_commands=",max_commands," unchanged_present_repeats=160")
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
