extends RefCounted
const RuntimeTests = preload("res://tests/vfx_runtime_bridge/test_runtime_bridge.gd")
const CityTests = preload("res://tests/city_presentation/test_world_view_city.gd")
const DirectorTests = preload("res://tests/presentation_vfx/test_director.gd")
class Capture extends "res://game/presentation/world_view.gd":
	var emitted: Array[Dictionary] = []
	func _draw_city() -> void: emitted.append({"asset":"ground"})
	func _draw_props() -> void: emitted.append({"asset":"legacy_props"})
	func _draw_city_ground(_command: Dictionary) -> void: emitted.append({"asset":"ground"})
	func _draw_player_outline(_command: Dictionary, _style: Dictionary) -> void: emitted.append({"asset":"player_outline"})
	func _draw_telegraph(_hazard: Dictionary) -> void: emitted.append({"asset":"warning"})
	func _draw_vfx_command(command: Dictionary) -> void: emitted.append({"asset":command.asset_id,"pass":command.render_pass,"world":command.world_anchor})
	func _sprite(asset_id: String, point: Vector2, _animation: String, _scale_value: float, _flip := false, _seconds := -1.0) -> void:
		emitted.append({"asset":asset_id,"world":point})
	func capture() -> Array:
		emitted.clear()
		_draw()
		return emitted.duplicate(true)
func run(t) -> void:
	var view := Capture.new()
	view.load_manifest()
	t.check(view.has_method("_draw_vfx_command"), "WorldView has a real raster command draw adapter")
	if not view.has_method("_draw_vfx_command"): view.free(); return
	var fixtures := RuntimeTests.new()
	var metadata := fixtures.raster_metadata()
	view._assets.merge(metadata,true)
	view._combat_bridge.set_asset_metadata(view._assets)
	var state: Dictionary = CityTests.new()._state()
	state.active_tick = 10; state.event_seq = 3
	state.projectiles.clear()
	var blade := fixtures.attack(1,10,"blade_slash",[100,220],state.run_id)
	var aim: Dictionary = DirectorTests.new().attack(2,"wall_cannon","evo_crossfire",10,46,"scheduled",{"shape":"circle","origin":[100,220],"direction":[1,0],"radius":56})
	aim.event_id = state.run_id+":2"; aim.payload.attack_id = state.run_id+":attack:2:0"
	var impact := {"event_id":state.run_id+":3","tick":10,"type":"projectile_impact","payload":{"projectile_id":8,"attack_id":state.run_id+":attack:3:0","base_item_id":"wall_cannon","position":[100,220],"radius":40}}
	view.consume_combat_events(fixtures.events([blade,aim,impact]),state)
	view.present_city(state,CityTests.new()._terrain())
	var emitted := view.capture()
	var names: Array = emitted.map(func(c): return c.asset)
	t.check(names.has("vfx_blade_crescent") and names.has("vfx_crossfire_ally_aim") and names.has("vfx_cannon_contact_blast"), "actual streamed WorldView traversal emits world ground and contact rasters")
	t.check(names.find("vfx_crossfire_ally_aim") < names.find("house_narrow"), "ground aim remains beneath city props")
	t.check(names.find("garrison_01") < names.find("vfx_blade_crescent") and names.find("vfx_blade_crescent") < names.find("house_narrow"), "world effect joins true actor/prop foot-depth order")
	t.check(names.find("vfx_cannon_contact_blast") > names.find("house_narrow") and names.find("vfx_cannon_contact_blast") < names.find("warning"), "contact overlay stays below final enemy warnings")
	if names.has("player_outline"): t.check(names.find("vfx_cannon_contact_blast") < names.find("player_outline"), "contact overlay stays below player-location outline")
	view._viewport_size = Vector2(450,800)
	t.check(view.capture().map(func(c): return c.asset) == names, "portrait keeps identical VFX/city depth-pass order")
	# A finite presentation uses the same command adapter and foot-depth merge.
	state.erase("world")
	view._map = {"props":[{"asset_id":"house_narrow","position":[100,224]}]}
	view.reset_presentation()
	state.event_seq = 1
	view.consume_combat_events(fixtures.events([blade]),state)
	view.present(state)
	emitted = view.capture(); names = emitted.map(func(c): return c.asset)
	t.check(names.find("vfx_blade_crescent") >= 0 and names.find("vfx_blade_crescent") < names.find("house_narrow"), "finite WorldView uses the same raster/depth adapter")
	t.check(names.find("warning") < names.find("garrison_01"), "finite player feedback remains above final warning raster")
	view.free()
	_fallback_boundary(t,fixtures,metadata)
	_live_rebase_gait(t,fixtures,metadata)
	_successful_tick_before_present(t,fixtures,metadata)
	_attack_pose_replay_floor(t,fixtures,metadata)
	_stale_batch_keeps_accepted_scene(t,fixtures,metadata)
	_catchup_rollback_clears_discarded_pose(t,fixtures,metadata)
func _fallback_boundary(t,fixtures,metadata: Dictionary) -> void:
	var view := Capture.new()
	view.load_manifest(); view._assets.merge(metadata,true)
	view._combat_bridge.set_asset_metadata(view._assets)
	var state: Dictionary = CityTests.new()._state()
	state.active_tick = 10; state.event_seq = 1
	state.projectiles[0].attack_id = state.run_id+":attack:1:0"
	state.projectiles[0].radius = 4
	view.present_city(state,CityTests.new()._terrain())
	t.check(not view._city_render_packet().upright.any(func(c): return c.id == "projectile:i:7"), "real drawable shell suppresses its exact generic projectile")
	var unapproved := view._assets.duplicate(true)
	unapproved.vfx_cannon_shell.vfx_approved = false
	view._combat_bridge.set_asset_metadata(unapproved)
	t.check(view._city_render_packet().upright.any(func(c): return c.id == "projectile:i:7"), "unapproved shell diagnostics never suppress generic projectile")
	unapproved.vfx_cannon_shell.vfx_approved = true
	unapproved.vfx_cannon_shell.path = "/tmp/shiganshina-vfx-missing.png"
	view._combat_bridge.set_asset_metadata(unapproved)
	t.check(view._city_render_packet().upright.any(func(c): return c.id == "projectile:i:7"), "missing actual shell bytes never suppress generic projectile")
	state.projectiles.clear()
	state.event_seq = 2
	view._combat_bridge.set_asset_metadata(view._assets)
	var damage := {"event_id":state.run_id+":2","tick":10,"type":"damage","payload":{"target_id":"rear","hp":10,"source_id":"blade_slash","attack_id":state.run_id+":attack:1:0"}}
	view.consume_combat_events(fixtures.events([damage]),state)
	view.consume_events(fixtures.events([damage]))
	t.check(view._effects.is_empty(), "drawable contact spark suppresses exact duplicate generic damage impact")
	var blocked := view._assets.duplicate(true)
	blocked.vfx_hit_spark.vfx_approved = false
	view._combat_bridge.set_asset_metadata(blocked)
	view.consume_events(fixtures.events([damage]))
	t.check(view._effects.size() == 1 and view._effects[0].asset == "impact_fx", "damage fallback is hit feedback and never a synthetic skill slash")
	view.free()

func _live_rebase_gait(t,fixtures,metadata: Dictionary) -> void:
	var view := Capture.new()
	view.load_manifest(); view._assets.merge(metadata,true)
	view._assets.garrison_01.gait = {"cycle_distance_px":64.0}
	view._combat_bridge.set_asset_metadata(view._assets)
	var state: Dictionary = CityTests.new()._state()
	state.projectiles.clear(); state.entities.clear()
	state.active_tick = 10; state.event_seq = 1
	state.player.velocity = [480.0,0.0]
	view._combat_bridge.consume(fixtures.events([fixtures.attack(1,10,"blade_slash",[100,210],state.run_id)]),state)
	view.consume_combat_events([],state)
	view.present_city(state,CityTests.new()._terrain())
	state.active_tick = 11; state.event_seq = 1
	state.world.origin_chunk = ["1","0"]; state.world.origin_revision = 1
	state.player.position = [-660.0,210.0]
	var terrain: Dictionary = CityTests.new()._terrain()
	terrain.origin_chunk = ["1","0"]; terrain.origin_revision = 1
	terrain.chunks[0].local_origin -= Vector2(768,0)
	for prop in terrain.chunks[0].props:
		prop.position -= Vector2(768,0); prop.render_bounds.position -= Vector2(768,0)
	view.consume_combat_events([],state)
	view.present_city(state,terrain)
	t.check(is_equal_approx(float(view._gait_tracks.player.distance),8.0), "successful-tick VFX ingest cannot double rebase or preadvance existing gait")
	t.check(view.combat_vfx_commands().any(func(c): return not c.has("diagnostic") and c.asset_id == "vfx_blade_crescent" and c.world_anchor == Vector2(-668,210)), "live city presentation keeps bridge translation independent of generic observation translation")
	view.free()

func _successful_tick_before_present(t,fixtures,metadata: Dictionary) -> void:
	var view := Capture.new()
	view.load_manifest(); view._assets.merge(metadata,true)
	view._combat_bridge.set_asset_metadata(view._assets)
	var state: Dictionary = CityTests.new()._state()
	state.erase("world"); state.projectiles.clear()
	state.active_tick = 9; state.event_seq = 0
	view.present(state.duplicate(true))
	state.active_tick = 10; state.event_seq = 1
	view.consume_combat_events(fixtures.events([fixtures.attack(1,10,"blade_slash",[100,210],state.run_id)]),state)
	t.check(view.combat_vfx_commands().any(func(c): return not c.has("diagnostic") and c.asset_id == "vfx_blade_crescent"), "reading current commands between dispatch and render cannot roll back to prior frame")
	view.present(state)
	t.check(view.combat_vfx_commands().any(func(c): return not c.has("diagnostic") and c.asset_id == "vfx_blade_crescent"), "successful-tick cast survives its first actual present")
	view.reset_presentation()
	state.event_seq = 2
	var damage := {"event_id":state.run_id+":2","tick":10,"type":"damage","payload":{"target_id":"rear","hp":90}}
	view.present(state)
	view.consume_combat_events(fixtures.events([damage]),state)
	view.consume_events(fixtures.events([damage]))
	t.check(view._attack_until == 0.0, "runtime damage feedback alone cannot start a player attack pose")
	view.free()

func _attack_pose_replay_floor(t,fixtures,metadata: Dictionary) -> void:
	var view := Capture.new()
	view.load_manifest(); view._assets.merge(metadata,true)
	view._combat_bridge.set_asset_metadata(view._assets)
	var state: Dictionary = CityTests.new()._state()
	state.erase("world"); state.projectiles.clear()
	state.active_tick = 10; state.event_seq = 1
	var attack_events: Array[Dictionary] = fixtures.events([fixtures.attack(1,10,"blade_slash",[100,210],state.run_id)])
	view.consume_combat_events(attack_events,state)
	view.present(state)
	var until: float = view._attack_until
	view._clock = 0.2
	view.consume_combat_events(attack_events,state)
	t.check(view._attack_until == until, "duplicate dispatch cannot extend the player attack pose clock")
	view.reset_presentation()
	view.present(state)
	view.combat_vfx_commands()
	view.consume_combat_events(attack_events,state)
	t.check(view._attack_until == 0.0, "restored historical event floor also prevents attack-pose replay")
	state.run_id = "same-seed-new-run"; state.event_seq = 1; state.active_tick = 1
	view.consume_combat_events(fixtures.events([fixtures.attack(1,1,"spin_slash",[100,210],state.run_id)]),state)
	t.check(view._attack_until > 0.0, "same-seed new run still receives its first actual attack pose")
	view.free()

func _stale_batch_keeps_accepted_scene(t,fixtures,metadata: Dictionary) -> void:
	var view := Capture.new()
	view.load_manifest(); view._assets.merge(metadata,true)
	view._combat_bridge.set_asset_metadata(view._assets)
	var state: Dictionary = CityTests.new()._state()
	state.erase("world"); state.projectiles.clear()
	state.active_tick = 10; state.event_seq = 1
	var accepted: Array[Dictionary] = fixtures.events([fixtures.attack(1,10,"blade_slash",[100,210],state.run_id)])
	view.consume_combat_events(accepted,state)
	view.present(state)
	var before: Array = view.combat_vfx_commands()
	var prior := state.duplicate(true)
	prior.active_tick = 9; prior.event_seq = 0
	view.consume_combat_events(accepted,prior)
	t.check(view._snapshot == state and view._combat_snapshot == state, "rejected stale batch cannot erase the accepted WorldView scene")
	t.check(view.combat_vfx_commands() == before, "rejected stale wrapper batch retains live effects and sequence floor")
	view.consume_combat_events(accepted,state)
	t.check(view.combat_vfx_commands() == before, "rejected stale batch cannot open historical replay through a cleared bridge")
	# A genuine rollback is accepted as restoration, without replaying events.
	var historical: Array[Dictionary] = fixtures.events([fixtures.attack(1,9,"blade_slash",[100,210],state.run_id)])
	prior.event_seq = 1
	view.consume_combat_events(historical,prior)
	view.present(prior)
	t.check(not view.combat_vfx_commands().any(func(c): return not c.has("diagnostic") and c.role == "cast") and view._attack_until == 0.0, "valid decreasing-tick restore preserves the historical event floor through visual reset")
	view.free()

func _catchup_rollback_clears_discarded_pose(t,fixtures,metadata: Dictionary) -> void:
	var view := Capture.new()
	view.load_manifest(); view._assets.merge(metadata,true)
	view._combat_bridge.set_asset_metadata(view._assets)
	var state: Dictionary = CityTests.new()._state()
	state.erase("world"); state.projectiles.clear()
	state.active_tick = 10; state.event_seq = 1
	var first: Array[Dictionary] = fixtures.events([fixtures.attack(1,10,"blade_slash",[100,210],state.run_id)])
	view.consume_combat_events(first,state)
	view.present(state.duplicate(true))
	var restored := state.duplicate(true)
	state.active_tick = 11; state.event_seq = 2
	view._clock = 0.1
	view.consume_combat_events(fixtures.events([fixtures.attack(2,11,"spin_slash",[100,210],state.run_id)]),state)
	view.consume_combat_events(first,restored)
	t.check(view._attack_until == 0.0 and view._clock == 0.0, "rollback between rendered frames clears discarded tick attack pose and visual clock")
	# The active tick can be equal when restoration changes the event watermark.
	state.active_tick = 10; state.event_seq = 2
	view._clock = 0.1
	view.consume_combat_events(fixtures.events([fixtures.attack(2,10,"spin_slash",[100,210],state.run_id)]),state)
	view.consume_combat_events(first,restored)
	t.check(view._attack_until == 0.0, "same-tick decreasing event sequence also clears discarded pose")
	view.free()
