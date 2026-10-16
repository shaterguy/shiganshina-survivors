extends RefCounted
# Unexecuted integration draft: real resident geometry; arranged clocks/positions.
const Support = preload("res://tests/loot_city/loot_city_support.gd")
const Loot = preload("res://game/loot/loot_rules.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Address = preload("res://game/world/world_address.gd")
var support := Support.new()

func run(t) -> void:
	_field_and_rebase(t)
	_coverage_and_blocked_candidates(t)
	await t.create_timer(0.3).timeout

func _field_and_rebase(t) -> void:
	var app = support.make(t,"geometry")
	if app == null: return
	var origin := Vector2(app.state.player.position[0],app.state.player.position[1])
	var rng: String = app.state.progression_rng_state
	var chest := support.field(t,app)
	if chest.is_empty() or chest.status != "placed": app.free(); return
	# Exact RED: set_position writes float zero; cold validation must compare
	# numeric meaning, while still rejecting malformed/non-finite coordinates.
	t.check(Loot.validate(app.state),"LOOT CITY generated float sentinel validates before serialization")
	for point in [[0,0],[0.0,0.0],[0,0.0],[-0.0,0.0],[0.0,-0.0]]:
		var numeric: Dictionary = app.state.duplicate(true)
		numeric.loot.chests[0].position = point
		t.check(Loot.validate(numeric),"LOOT CITY zero sentinel accepts exact numeric representations")
		var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(numeric,"",true,true))
		t.check(Loot.validate(roundtrip),"LOOT CITY numeric sentinel survives precise save JSON roundtrip")
	for point in [["0",0],[false,0],[NAN,0],[INF,0],[-INF,0],[0],[0,0,0],{},null,[0.001,0]]:
		var malformed: Dictionary = app.state.duplicate(true)
		malformed.loot.chests[0].position = point
		t.check(not Loot.validate(malformed),"LOOT CITY sentinel rejects malformed shape, type, nonfinite and nonzero values")
	var local := Loot.local_position(app.state,chest)
	t.check(local.get("ok",false),"LOOT CITY field stable address localizes")
	if not local.get("ok",false): app.free(); return
	var radius: float = origin.distance_to(local.position)
	t.check(radius >= 159.999 and radius <= 240.001,"LOOT CITY actual field placement respects 160..240 radius")
	var helper = app.simulation._streamed
	t.check(helper._world.covered(Helper.segment_rect(origin,local.position,8.0)),"LOOT CITY full field sweep is resident")
	var walk: Dictionary = helper.walkable(local.position,8.0)
	var sweep: Dictionary = helper.sweep(origin,local.position-origin,8.0)
	t.check(walk.get("ok",false) and walk.get("walkable",false) and sweep.get("ok",false) and sweep.position.distance_squared_to(local.position) <= 0.0001,"LOOT CITY independent real radius8 sweep reaches field chest")
	t.check(helper.query_status().get("ok",false) and app.state.progression_rng_state == rng,"LOOT CITY placement keeps query status and progression RNG")
	t.check(chest.stage == "city" and chest.position == [0.0,0.0] and Address.parse(chest.address.chunk).ok,"LOOT CITY placement stores normalized absolute address")
	# Keep one generated placement and add the next due source behind its retry
	# deadline. Pending is arranged, not evidence of natural placement failure.
	app.state.active_tick = 32400
	app.state.survival_tick = 32400
	app.simulation._add_loot(app.state,Loot.field_spec(1),origin)
	app.state.loot.next_retry_tick = 32460
	var expected: Dictionary = app.state.loot.duplicate(true)
	t.check(expected.chests.size() == 2 and expected.chests[0].status == "placed" and expected.chests[1].status == "pending","LOOT CITY fixture has placed and pending sources")
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(app.state,"",true,true))
	var restored: Dictionary = app._city_runtime.refresh_coverage(decoded)
	t.check(restored.get("ok",false),"LOOT CITY pending/placed JSON cold restore uses real geometry")
	if not restored.get("ok",false): app.free(); return
	t.check(support.same(restored.state.loot,expected),"LOOT CITY cold restore preserves IDs, addresses and retry deadline")
	app._adopt_city_simulation(restored.simulation)
	app.state = restored.state
	var events: Array[Dictionary] = []
	app.simulation._update_loot(app.state,events)
	t.check(support.same(app.state.loot,expected),"LOOT CITY cold resume cannot retry pending source early")
	# A genuine Core step performs the rebase; no manual address/origin editing.
	app.state.player.position = [1152.0,384.0]
	if not support.refresh(t,app,"pre-rebase resident window"): app.free(); return
	var old_origin: Array = app.state.world.origin_chunk.duplicate()
	var old_revision: int = app.state.world.origin_revision
	var old_local: Vector2 = Loot.local_position(app.state,app.state.loot.chests[0]).position
	var commands: Array[Dictionary] = []
	app.simulation.step(app.state,Vector2.ZERO,commands)
	t.check(app.simulation.step_status().get("ok",false) and app.state.active_tick == 32401,"LOOT CITY actual Core rebase step commits")
	t.check(app.state.world.origin_chunk != old_origin and app.state.world.origin_revision == old_revision+1,"LOOT CITY actual step advances origin once")
	t.check(support.same(app.state.loot,expected),"LOOT CITY actual rebase preserves every chest ID/address/status")
	var new_local := Loot.local_position(app.state,app.state.loot.chests[0])
	t.check(new_local.get("ok",false) and new_local.position.distance_to(old_local-Vector2(768,0)) < 0.001,"LOOT CITY localization shifts once while absolute chest remains fixed")
	var rebased: Dictionary = app._city_runtime.refresh_coverage(JSON.parse_string(JSON.stringify(app.state,"",true,true)))
	t.check(rebased.get("ok",false) and support.same(rebased.get("state",{}).get("loot",{}),expected),"LOOT CITY post-rebase real cold restore preserves both source states")
	app.free()

func _coverage_and_blocked_candidates(t) -> void:
	var app = support.make(t,"coverage")
	if app == null: return
	var helper = app.simulation._streamed
	var resident_before: PackedByteArray = var_to_bytes(helper._world._chunks)
	var identity: Dictionary = helper._prepared_identity.duplicate(true)
	var player := Vector2(app.state.player.position[0],app.state.player.position[1])
	var mismatched: Dictionary = app.state.duplicate(true)
	mismatched.world.origin_chunk = ["999","999"]
	t.check(not app.simulation._loot_coverage_present(mismatched,Helper.segment_rect(player,player,8.0)),"LOOT CITY mismatched private fixture origin is conservatively rejected")
	t.check(helper.query_status().get("ok",false) and helper._world._last_error.is_empty(),"LOOT CITY mismatched origin does not poison resident query state")
	var blocked := {}
	for prop in helper._world.localized_chunk("0,0").props:
		if prop.collision_mask != 0 and player.distance_to(prop.ground_footprint.get_center()) <= 512.0:
			blocked = prop
			break
	t.check(not blocked.is_empty(),"LOOT CITY blocked-candidate fixture uses an actual collidable city prop")
	if not blocked.is_empty():
		t.check(not app.simulation._loot_path_clear(app.state,player,blocked.ground_footprint.get_center()),"LOOT CITY resident solid candidate is rejected")
		t.check(helper.query_status().get("ok",false),"LOOT CITY ordinary blocked candidate does not poison query status")
	# Deliberately retain the old resident window while moving the fixture player
	# onto a reserved road beyond its east boundary. No missing geometry is loaded.
	var max_x := -100000.0
	for key in helper._world.chunk_keys():
		var chunk: Dictionary = helper._world.localized_chunk(key)
		max_x = maxf(max_x,float(chunk.local_origin.x)+768.0)
	var absent := Vector2(max_x+384.0,384.0)
	var absent_address := Address.normalize(app.state.world.origin_chunk,absent)
	t.check(absent_address.get("ok",false) and not helper._world.chunk_keys().has(Address.key(absent_address.chunk)),"LOOT CITY candidate truly lies outside resident coverage")
	app.state.player.position = [absent.x,absent.y]
	app.state.active_tick = 10800
	app.state.survival_tick = 10800
	var events: Array[Dictionary] = []
	app.simulation._update_loot(app.state,events)
	t.check(app.state.loot.chests.size() == 1 and app.state.loot.chests[0].status == "pending" and app.state.loot.next_retry_tick == 10860,"LOOT CITY missing coverage keeps source pending with bounded retry")
	var pending: Dictionary = app.state.loot.duplicate(true)
	app.simulation._update_loot(app.state,events)
	t.check(support.same(app.state.loot,pending) and events.is_empty(),"LOOT CITY same-tick unavailable placement neither duplicates nor pays")
	t.check(helper.query_status().get("ok",false) and helper._world._last_error.is_empty(),"LOOT CITY unavailable candidates avoid public-query failure contamination")
	t.check(var_to_bytes(helper._world._chunks) == resident_before and helper._prepared_identity == identity,"LOOT CITY placement does not mutate resident terrain or prepared identity")
	# Fresh real coverage must accept the pending address without rewriting it.
	if support.refresh(t,app,"pending source in newly hydrated road"):
		t.check(support.same(app.state.loot,pending),"LOOT CITY cold hydration preserves unavailable pending source/address")
		app.state.active_tick = 10860
		app.state.survival_tick = 10860
		app.simulation._update_loot(app.state,events)
		t.check(app.state.loot.chests[0].status == "placed" and app.state.loot.chests[0].id == pending.chests[0].id,"LOOT CITY recovered coverage places same source at retry deadline")
	app.free()
