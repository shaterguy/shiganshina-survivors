extends RefCounted
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Renderer = preload("res://game/presentation/combat_vfx_renderer.gd")
const Bridge = preload("res://game/presentation/combat_vfx_bridge.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Actual = preload("res://tests/fantasy_vfx/test_actual_fantasy_vfx.gd")
const Existing = preload("res://tests/core/test_rebuild_attack_events.gd")
var seen_assets: Dictionary = {}
const Gate = preload("res://tools/build/export_readiness.gd")
func run(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	var catalog := Catalog.new()
	var ids := []
	for path in ["res://docs/art/vfx/evolution-runtime-candidate.json","res://docs/art/vfx/fantasy-runtime-candidate.json"]:
		var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
		for id in source.assets:
			ids.append(id)
			t.check(manifest.assets.has(id),"new original VFX is actually registered "+id)
			if not manifest.assets.has(id): continue
			var asset: Dictionary = manifest.assets[id]
			t.check(asset.vfx_approved == false and asset.get("native_reviewed") == false and asset.get("final_art_approved") == false,"development activation never claims native or final approval "+id)
			t.check(asset.get("development_render_enabled") == true and asset.get("review_status") == "development_enabled_native_review_pending","development activation is explicit and separately labeled "+id)
			t.check(asset.sha256 == source.assets[id].sha256 and catalog.validate_art_metadata(id,asset).is_empty(),"registration preserves validated original raster identity "+id)
			t.check(Gate.new().is_runtime_asset_path(asset),"raw export path includes registered development VFX "+id)
	t.check(ids.size() == 10,"exactly ten new original VFX entries")
	t.check(manifest.art_revision_status.final_export_allowed == false and manifest.art_revision_status.blocked_character_ids.size() == 5 and not Gate.new().validate(manifest).ok,"five character blocks and final export gate remain closed")
	var reviewed: Array = manifest.assets.keys().filter(func(id): return manifest.assets[id].get("vfx_approved",false) == true)
	t.check(reviewed.size() == 5,"existing five reviewed VFX remain the only vfx_approved assets")
	t.check(catalog.has_method("render_problem"),"Catalog exposes shared strict development render policy")
	if not catalog.has_method("render_problem") or not manifest.assets.has("vfx_chain_lightning"): return
	t.check(catalog.validate(manifest).all(func(problem): return problem in ["missing_art:vfx_dash_compressed_gas","missing_art:vfx_wire_taut","missing_art:vfx_dash_cross_tip","missing_art:vfx_reentry_triple","missing_art:vfx_ally_gas_swoop","missing_art:vfx_ally_arrival_cut"]),"new ten and existing five assets validate; six unrelated original art gaps remain explicit")
	_gates(t,catalog,manifest)
	_reconfigure_cache(t,manifest)
	for pair in [["chain_lightning",""],["chain_lightning","evo_storm_chain"],["fire_zone",""],["fire_zone","evo_inferno_zone"]]: _public_flow(t,manifest,pair[0],pair[1])
	for base in ["blade_slash","spin_slash","wall_cannon"]: _existing_public_flow(t,manifest,base,"")
	for evo in ["evo_wing_cut","evo_crossfire"]: _existing_public_flow(t,manifest,"blade_slash" if evo == "evo_wing_cut" else "wall_cannon",evo)
	for id in ids: t.check(seen_assets.has(id),"all ten registered originals are exercised by actual Core public Bridge commands "+id)
func _gates(t,catalog,manifest: Dictionary) -> void:
	var id := "vfx_chain_lightning"
	var asset: Dictionary = manifest.assets[id]
	t.check(catalog.render_problem(id,asset).is_empty(),"registered development metadata and actual PNG pass shared policy")
	var effect := Director.new()._make_effect(catalog.recipe("chain_lightning","","cast"),{"attack_id":"gate:1:0","cast_id":"gate:1","origin":[0,0],"direction":[1,0],"geometry":{"shape":"line","origin":[0,0],"direction":[1,0],"length":60,"width":8}},1)
	var effects: Array[Dictionary] = [effect]
	for change in [{"key":"development_render_enabled","value":false},{"key":"development_render_enabled","value":"true"},{"key":"development_render_enabled","value":1},{"key":"vfx_approved","value":"true"},{"key":"native_reviewed","value":true},{"key":"native_reviewed","value":"false"},{"key":"final_art_approved","value":"false"},{"key":"review_status","value":"approved"},{"key":"anchor_px","value":[0,32]},{"key":"sha256","value":"0".repeat(64)}]:
		var bad: Dictionary = asset.duplicate(true)
		bad[change.key] = change.value
		t.check(not catalog.render_problem(id,bad).is_empty(),"shared policy rejects unsafe or corrupt development metadata "+change.key+str(change.value))
		var rendered := Renderer.new().commands(effects,{"tick":1,"origin_revision":0,"asset_metadata":{id:bad}})
		t.check(rendered.size() == 1 and rendered[0].has("diagnostic"),"public Renderer rejects unsafe development metadata "+change.key)
	var corrupted: Dictionary = asset.duplicate(true)
	corrupted.path = "/tmp/fantasy-vfx-invalid-original.png"
	var file := FileAccess.open(corrupted.path,FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1,2,3,4]));file.close()
	t.check(catalog.render_problem(id,corrupted) == "asset_hash_mismatch","shared policy rejects changed original bytes")
	var inactive: Dictionary = asset.duplicate(true)
	inactive.erase("development_render_enabled")
	t.check(catalog.render_problem(id,inactive) == "unapproved_art","ordinary false candidate cannot silently enter development path")
func _public_flow(t,manifest: Dictionary,base: String,evolution: String) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {base:1}
	if evolution != "":
		state = Actual.new()._earned_empty(t,sim,evolution)
		if state.is_empty(): return
	var commands := []
	for i in (12 if base == "chain_lightning" else 1): commands.append(F.spawn("public-"+str(i),[80+i*40,0],"brute"))
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,commands)
	var snapshot: Dictionary = sim.snapshot(state)
	state.player.attack_ready_ticks[base] = 999999
	var bridge := Bridge.new(manifest)
	t.check(bridge.consume(events,snapshot),"public Bridge ingests actual Core tick "+base+evolution)
	var drawn := bridge.present(snapshot)
	_record_draws(drawn)
	t.check(not drawn.is_empty() and not drawn.any(func(c): return c.has("diagnostic")),"registered public path has no missing/gated/corrupt draw commands "+base+evolution)
	for event in events.filter(func(e): return e.type == "player_attack" and e.payload.base_item_id == base and e.payload.phase == "executed"):
		var found := drawn.filter(func(c): return c.attack_id == event.payload.attack_id)
		t.check(found.size() == 1 and found[0].contact_geometry == event.payload.geometry and found[0].atlas_region.position == Vector2.ZERO,"public command preserves exact real contact and frame0 "+base)
	bridge.consume(events,snapshot)
	t.check(bridge.present(snapshot) == drawn,"public bridge deduplicates actual event replay and freezes active-clock phase")
	var relevant := "vfx_storm_chain" if evolution == "evo_storm_chain" else ("vfx_inferno_zone" if evolution == "evo_inferno_zone" else ("vfx_chain_lightning" if base == "chain_lightning" else "vfx_fire_zone"))
	for change in [{"key":"sha256","value":"0".repeat(64),"diagnostic":"asset_hash_mismatch"},{"key":"development_render_enabled","value":false,"diagnostic":"unapproved_art"},{"key":"development_render_enabled","value":"true","diagnostic":"unapproved_art"},{"key":"vfx_approved","value":"true","diagnostic":"unapproved_art"}]:
		var rejected_meta: Dictionary = manifest.duplicate(true)
		rejected_meta.assets[relevant][change.key] = change.value
		var bad_bridge := Bridge.new(rejected_meta)
		bad_bridge.consume(events,snapshot)
		t.check(bad_bridge.present(snapshot).any(func(c): return c.get("asset_id") == relevant and c.get("diagnostic") == change.diagnostic),"actual public Bridge rejects inactive/string/corrupt development metadata "+change.key)
	if base != "fire_zone": return
	var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(snapshot)))
	t.check(restored.get("ok",false),"actual public fire state cold restores without presentation fields")
	var cold_commands := Bridge.new(manifest).present(snapshot)
	t.check(cold_commands.size() == 1 and cold_commands[0].get("role") == "area","cold public Bridge reconstructs only the actual pending floor, not historical contact flashes")
	var last := int(state.player_attack_instances[-1].execute_tick)
	while state.active_tick < last:
		events = F.step(sim,state,Vector2.ZERO)
		snapshot = sim.snapshot(state)
		bridge.consume(events,snapshot)
		drawn = bridge.present(snapshot)
		_record_draws(drawn)
		t.check(_no_diagnostics(drawn),"every actual fire stage/floor and killing spark resolves registered art without diagnostics")
		if state.active_tick < last: t.check(drawn.any(func(c): return c.role == "area"),"public ground field persists between real stages")
	if evolution != "": t.check(drawn.any(func(c): return c.asset_id == "vfx_crossfire_contact_blast" and c.role == "impact"),"final real eruption reaches registered public impact path")

func _record_draws(commands: Array) -> void:
	for command in commands:
		if not command.has("diagnostic"): seen_assets[command.asset_id] = true
func _no_diagnostics(commands: Array) -> bool:
	return not commands.any(func(c): return c.has("diagnostic"))
func _existing_public_flow(t,manifest: Dictionary,base: String,evolution: String) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim) if evolution.is_empty() else Existing.evolved_state(sim,X.chapter(),evolution)
	if evolution.is_empty(): state.equipment = {base:1}
	var bridge := Bridge.new(manifest)
	var contacts := 0
	for index in (70 if not evolution.is_empty() or base == "wall_cannon" else 1):
		var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("registered-existing",[45,0],"brute")] if index == 0 else [])
		state.player.attack_ready_ticks[base] = 999999
		var snapshot: Dictionary = sim.snapshot(state)
		t.check(bridge.consume(events,snapshot),"registered existing cast ingests real Core tick "+base+evolution)
		var commands := bridge.present(snapshot)
		_record_draws(commands)
		t.check(_no_diagnostics(commands),"registered existing VFX has no missing/invalid/gated original "+base+evolution)
		for event in events.filter(func(e): return e.type == "player_attack" and e.payload.phase == "executed"):
			contacts += 1
			t.check(commands.any(func(c): return not c.has("diagnostic") and c.attack_id == event.payload.attack_id),"actual base/ultimate contact reaches public registered commands "+base+evolution)
	t.check(contacts == (2 if not evolution.is_empty() else 1),"actual base/ultimate execution count unchanged "+base+evolution)

class CountingBridge:
	extends Bridge
	var original_checks := 0
	func _raster_problem(asset_id: String) -> String:
		if not _raster_validation.has(asset_id): original_checks += 1
		return super._raster_problem(asset_id)
func _reconfigure_cache(t,manifest: Dictionary) -> void:
	var sim = X.simulation()
	var state: Dictionary = X.state(sim)
	state.equipment = {"chain_lightning":1}
	var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("cache-target",[80,0],"brute")])
	var snapshot: Dictionary = sim.snapshot(state)
	var metadata := manifest.duplicate(true)
	var id := "vfx_chain_lightning"
	var bytes := FileAccess.get_file_as_bytes(metadata.assets[id].path)
	metadata.assets[id].path = "/tmp/fantasy-vfx-reconfigure.png"
	var file := FileAccess.open(metadata.assets[id].path,FileAccess.WRITE)
	file.store_buffer(bytes);file.close()
	var bridge := CountingBridge.new(metadata)
	bridge.consume(events,snapshot)
	var drawn := bridge.present(snapshot)
	t.check(_no_diagnostics(drawn),"first development config validates original and draws")
	var checks := bridge.original_checks
	for index in 5: t.check(bridge.present(snapshot) == drawn,"immutable config reuses identical public commands")
	t.check(bridge.original_checks == checks,"public Bridge reuses its existing one original-byte cache across frames")
	# Mutate only the isolated copy, then rebuild the metadata configuration.
	file = FileAccess.open(metadata.assets[id].path,FileAccess.WRITE)
	file.store_buffer(PackedByteArray([1,2,3]));file.close()
	bridge.set_asset_metadata(metadata)
	t.check(bridge.present(snapshot).any(func(c): return c.get("asset_id") == id and c.get("diagnostic") == "asset_hash_mismatch"),"reconfigure cannot reuse previous success after original bytes change")
	t.check(bridge.original_checks > checks,"metadata reconfiguration invalidates original-byte validation")
	var fresh := CountingBridge.new(metadata)
	fresh.consume(events,snapshot)
	t.check(fresh.present(snapshot).any(func(c): return c.get("asset_id") == id and c.get("diagnostic") == "asset_hash_mismatch"),"new Bridge cannot inherit another config's success")
	file = FileAccess.open(metadata.assets[id].path,FileAccess.WRITE)
	file.store_buffer(bytes);file.close()
	bridge.set_asset_metadata(metadata)
	t.check(_no_diagnostics(bridge.present(snapshot)),"reconfigure revalidates repaired bytes instead of retaining old failure")
