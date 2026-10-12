extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Catalog = preload("res://game/presentation/combat_vfx_catalog.gd")
const Gate = preload("res://tools/build/export_readiness.gd")
const IDS := ["vfx_dash_compressed_gas","vfx_dash_cross_tip","vfx_reentry_triple","vfx_ally_gas_swoop","vfx_ally_arrival_cut"]
# Removing any new registration, bypassing the strict gate, changing contact
# geometry, or replacing the registered texture with generic art fails this suite.
class Capture extends "res://game/presentation/world_view.gd":
	var pixels: Array = []
	var captured_transform := Transform2D.IDENTITY
	func _world_transform(point: Vector2, angle := 0.0, scale_value := Vector2.ONE) -> void:
		captured_transform = Transform2D(angle,point).scaled_local(scale_value)
	func _world_region(texture: Texture2D, rect: Rect2, region: Rect2, color := Color.WHITE) -> void:
		for id in _textures:
			if _textures[id] == texture and id in IDS:
				pixels.append({"asset_id":id,"rect":rect,"region":region,"image":texture.get_image().get_region(Rect2i(region)),"transform":captured_transform,"color":color})
	func _world_rect(_texture: Texture2D, _rect: Rect2, _tiled: bool, _color := Color.WHITE) -> void: pass
	func capture() -> void:
		pixels.clear(); _draw()
func run(t) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	for id in IDS: t.check(manifest.assets.has(id),"remaining original is registered: "+id)
	if not manifest.assets.has_all(IDS): return
	var descriptor: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/vfx/remaining-runtime-candidate.json"))
	t.check(descriptor.assets.size() == 5 and descriptor.assets.has_all(IDS),"descriptor adds exactly the five authored originals")
	var catalog := Catalog.new()
	t.check(catalog.validate(manifest) == ["missing_art:vfx_wire_taut"],"only absent anchor-conditional wire remains a catalog diagnostic")
	for id in IDS:
		var candidate: Dictionary = descriptor.assets[id].duplicate(true)
		candidate.merge({"development_render_enabled":true,"native_reviewed":false,"final_art_approved":false,"review_status":"development_enabled_native_review_pending"},true)
		t.check(manifest.assets[id] == candidate and candidate.vfx_approved == false,"exact raster descriptor is activated without visual approval: "+id)
		t.check(catalog.render_problem(id,candidate).is_empty() and Gate.new().is_runtime_asset_path(candidate),"strict raster and export policy accept registered original: "+id)
		for key in ["development_render_enabled","native_reviewed","final_art_approved","vfx_approved"]:
			var bad := candidate.duplicate(true); bad[key] = "true"
			t.check(not catalog.render_problem(id,bad).is_empty() and not Gate.new().is_runtime_asset_path(bad),"string flags cannot bypass either policy: "+id+key)
	t.check(not manifest.art_revision_status.final_export_allowed and manifest.art_revision_status.blocked_character_ids.size() == 5 and not Gate.new().validate(manifest).ok,"final export and five character blocks stay closed")
	for base in ["odm_dash","reentry_combo","ally_cover"]:
		for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2(0.6,0.8)]: _flow(t,manifest,base,direction)
	_reentry_outcomes(t)
func _flow(t,manifest: Dictionary,base: String,direction: Vector2) -> void:
	var sim = F.simulation(t)
	var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
	state.equipment = {base:1}
	var view := Capture.new(); view.load_manifest(); view._viewport_size = Vector2(1600,900)
	var seen := {}; var contacts := 0; var impacts := 0; var first_tick := 0
	var command_peak := 0; var initial_player: Array = state.player.position.duplicate()
	for tick in range(1,35):
		var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO,[F.spawn("remaining-target",[direction.x*60,direction.y*60],"brute")] if tick == 1 else [])
		state.player.attack_ready_ticks[base] = 999999
		var snapshot: Dictionary = sim.snapshot(state); var before := snapshot.duplicate(true); var events_before := events.duplicate(true)
		view.consume_combat_events(events,snapshot); view.present(snapshot)
		var drawn: Array = view.combat_vfx_commands()
		command_peak = maxi(command_peak,drawn.size())
		t.check(not drawn.any(func(c): return c.has("diagnostic")),"actual Core path has no missing/gated/invalid commands: "+base)
		t.check(not drawn.any(func(c): return c.get("component") == "wire"),"no wire is invented without a Core wire anchor")
		t.check(state.player.position == initial_player,"presentation does not invent actor displacement: "+base)
		for event in events:
			if event.type == "player_attack" and event.payload.base_item_id == base and event.payload.phase == "executed":
				contacts += 1; first_tick = int(snapshot.active_tick)
				var owned := drawn.filter(func(c): return c.get("attack_id") == event.payload.attack_id and c.get("role") != "impact")
				t.check(owned.size() == (2 if base == "odm_dash" else 1),"one actual cast has its exact mandatory raster layers: "+base)
				for c in owned:
					t.check(c.contact_geometry == event.payload.geometry and c.atlas_region.position == Vector2.ZERO,"first contact preserves Core geometry and frame zero")
					if base == "odm_dash":
						var origin := _vec(event.payload.origin)
						var target := origin+_vec(event.payload.direction).normalized()*float(event.payload.geometry.length)
						t.check(c.world_anchor.is_equal_approx(target if c.component == "tip" else origin),"dash main/tip use exact origin/endpoint in every direction")
						t.check(c.contact_size == (Vector2(8,8) if c.component == "tip" else Vector2(event.payload.geometry.length,event.payload.geometry.width)),"dash raster footprint never enlarges actual line")
					elif base == "reentry_combo":
						var hits := events.filter(func(e): return e.type == "damage" and e.payload.get("attack_id") == event.payload.attack_id)
						t.check(hits.size() == 1 and c.world_anchor.is_equal_approx(_vec(hits[0].payload.position)),"triple contact stays on actual damage position")
						t.check(c.contact_size == Vector2(36,36),"single-target triple uses separate 36px presentation bounds, never acquisition radius80")
			if event.type == "projectile_impact" and event.payload.base_item_id == base:
				impacts += 1
				var arrival := drawn.filter(func(c): return c.get("asset_id") == "vfx_ally_arrival_cut")
				t.check(arrival.size() == 1 and arrival[0].world_anchor.is_equal_approx(_vec(event.payload.position)),"arrival cut starts once at actual projectile impact")
				if arrival.size() == 1: t.check(arrival[0].contact_size == Vector2(8,8) and event.payload.radius == 0.0 and arrival[0].atlas_region.position == Vector2.ZERO,"zero-splash arrival stays 8px contact with no cannon explosion")
		for c in drawn:
			if c.get("asset_id") not in IDS: continue
			seen[c.asset_id] = true
			if c.asset_id == "vfx_ally_gas_swoop":
				var p: Array = snapshot.projectiles.filter(func(p): return p.id == c.projectile_id)
				t.check(p.size() == 1 and c.world_anchor.is_equal_approx(_vec(p[0].position)),"gas swoop follows real projectile position")
				t.check(c.contact_size == Vector2(8,8),"swoop uses actual projectile radius rather than acquisition range")
		view.capture()
		var relevant := drawn.filter(func(c): return c.get("asset_id") in IDS)
		t.check(view.pixels.size() == relevant.size(),"full WorldView traversal emits every mandatory registered raster exactly once")
		for pixel in view.pixels:
			var matches := relevant.filter(func(c): return c.asset_id == pixel.asset_id and c.atlas_region == pixel.region)
			t.check(matches.size() == 1,"emitted atlas cell matches one real VFX command")
			if matches.size() != 1: continue
			var c: Dictionary = matches[0]; var source := Image.new(); source.load_png_from_buffer(FileAccess.get_file_as_bytes(manifest.assets[c.asset_id].path))
			t.check(pixel.image.get_data() == source.get_region(Rect2i(c.atlas_region)).get_data(),"drawn bytes equal registered original atlas cell")
			t.check(pixel.transform.origin.is_equal_approx(view._screen(c.world_anchor)) and pixel.rect == c.local_rect,"actual draw uses command anchor and authored pivot")
			t.check(pixel.transform.x.is_equal_approx(Vector2(c.scale.x,0).rotated(c.rotation)) and pixel.transform.y.is_equal_approx(Vector2(0,c.scale.y).rotated(c.rotation)),"actual draw keeps directional scale and rotation")
		view.consume_combat_events(events,snapshot)
		t.check(view.combat_vfx_commands() == drawn,"duplicate successful tick cannot duplicate or move effect")
		t.check(snapshot == before and events == events_before and sim.snapshot(state) == before,"VFX/draw does not mutate Core state, snapshot, or events")
		if base != "ally_cover" and tick >= first_tick+10: t.check(relevant.is_empty(),"remaining contact retires at authored ten ticks")
	t.check(contacts == 1 and impacts == (1 if base == "ally_cover" else 0),"actual Core cast/contact count remains exact: "+base)
	var expected := ["vfx_dash_compressed_gas","vfx_dash_cross_tip"] if base == "odm_dash" else (["vfx_reentry_triple"] if base == "reentry_combo" else ["vfx_ally_gas_swoop","vfx_ally_arrival_cut"])
	t.check(seen.has_all(expected),"every required raster reaches real Core event and full WorldView draw: "+base)
	t.check(command_peak <= 3,"single-cast draw cost stays bounded at two layers plus one hit spark")
	print("REMAINING_VFX_FLOW ",base," direction=",direction," observed=",seen.keys()," peak=",command_peak)
	view.free()
func _vec(a) -> Vector2: return Vector2(a[0],a[1])

func _reentry_outcomes(t) -> void:
	for outcome in ["kill","miss","armor_blocked"]:
		var sim = F.simulation(t)
		var state: Dictionary = sim.new_run(F.chapter(),42,F.run_config())
		state.equipment = {"reentry_combo":1,"blade_slash":1} if outcome == "miss" else {"reentry_combo":1}
		state.player.attack_ready_ticks = {"reentry_combo":999999,"blade_slash":999999}
		if outcome == "armor_blocked":
			state.active_tick = 108000; state.survival_tick = 108000
			F.step(sim,state,Vector2.ZERO,[F.final_command(state)])
			state.player.position = [state.entities[0].position[0]-50,state.entities[0].position[1]]
		else:
			F.step(sim,state,Vector2.ZERO,[F.spawn("outcome-target",[45,0],"brute")])
			state.entities[0].hp = 1.0
		state.player.attack_ready_ticks.reentry_combo = state.active_tick
		if outcome == "miss": state.player.attack_ready_ticks.blade_slash = state.active_tick
		var events: Array[Dictionary] = F.step(sim,state,Vector2.ZERO)
		var actual := events.filter(func(e): return e.type == "player_attack" and e.payload.base_item_id == "reentry_combo" and e.payload.phase == "executed")
		t.check(actual.size() == 1,"outcome is based on real executed reentry: "+outcome)
		var own_damage := events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "reentry_combo")
		t.check(own_damage.size() == (1 if outcome == "kill" else 0),"actual reentry outcome distinguishes damage from miss/block: "+outcome)
		if outcome == "armor_blocked": t.check(events.any(func(e): return e.type == "armor_blocked" and e.payload.source_id == "reentry_combo"),"real final armor generates armor_blocked, not damage")
		else: t.check(state.entities.is_empty(),"actual killing hit removes target before successful snapshot")
		var view := Capture.new(); view.load_manifest()
		var snapshot: Dictionary = sim.snapshot(state)
		view.consume_combat_events(events,snapshot); view.present(snapshot); view.capture()
		var triples := view.combat_vfx_commands().filter(func(c): return c.get("asset_id") == "vfx_reentry_triple")
		t.check(triples.size() == (1 if outcome == "kill" else 0),"no success triple on miss or armor block: "+outcome)
		t.check(view.pixels.size() == triples.size(),"outcome reaches actual draw boundary without fallback triple")
		if outcome == "kill" and triples.size() == 1:
			var contact := _vec(own_damage[0].payload.position)
			t.check(triples[0].world_anchor.is_equal_approx(contact),"killing reentry survives target removal at exact hit point")
			state.player.attack_ready_ticks.reentry_combo = 999999
			var next: Array[Dictionary] = F.step(sim,state,Vector2.LEFT)
			view.consume_combat_events(next,sim.snapshot(state)); view.present(sim.snapshot(state))
			triples = view.combat_vfx_commands().filter(func(c): return c.get("asset_id") == "vfx_reentry_triple")
			t.check(triples.size() == 1 and triples[0].world_anchor.is_equal_approx(contact),"reentry recovery cannot follow moving player or removed actor")
			var cold := Capture.new(); cold.load_manifest(); cold.present(sim.snapshot(state))
			t.check(cold.combat_vfx_commands().is_empty(),"cold snapshot never invents historical reentry contact")
			cold.free()
		view.free()
