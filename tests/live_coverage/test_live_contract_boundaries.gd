extends RefCounted
const F = preload("res://tests/live_coverage/live_fixture.gd")
const Motion = preload("res://tests/terrain_mobility/motion_fixture.gd")
const Planner = preload("res://game/world/mobility_anchor_query.gd")

# These subclasses expose the existing extension callbacks. They do not emulate
# admission, hydration or preparation: each callback delegates to production.
class CallbackRuntime:
	extends "res://game/app/prepared_city_runtime.gd"
	var calls: Array = []
	func _new_core(snapshot: Dictionary = {}):
		calls.append("runtime.new_core")
		return super._new_core(snapshot)
class CallbackProvider:
	extends "res://game/director/streamed_chapter_provider.gd"
	var calls: Array = []
	func load_chapter(id: String) -> Dictionary:
		calls.append("provider.load_chapter")
		return super.load_chapter(id)
class CallbackDisk:
	extends "res://game/persistence/world_delta_store.gd"
	var calls: Array = []
	func begin_verified_read() -> void:
		calls.append("disk.begin_verified_read")
		super.begin_verified_read()
	func verify_root(root: Dictionary) -> Dictionary:
		calls.append("disk.verify_root")
		return super.verify_root(root)
	func hydrate(root: Dictionary, chunks: Array) -> Dictionary:
		calls.append("disk.hydrate")
		return super.hydrate(root,chunks)
class SwitchProvider:
	extends RefCounted
	var chapter: Dictionary
	var blocked := false
	var reads := 0
	func _init(value: Dictionary) -> void: chapter = value.duplicate(true)
	func rules_version() -> String: return "dev5"
	func load_chapter(_id: String) -> Dictionary:
		reads += 1
		return {"ok":false,"error_code":"definition_missing"} if blocked else {"ok":true,"chapter":chapter.duplicate(true)}

func run(t) -> void:
	var s := F.make(t)
	if s.is_empty(): return
	t.check(s.runtime.has_method("refresh_live_coverage"),"live contract boundary requires the separate private preparation API")
	if not s.runtime.has_method("refresh_live_coverage"): return
	_dynamic_matrix(t,s)
	_boost_anchor_matrix(t,s)
	_custom_callbacks(t,s)
	_cold_preamble(t,s)
	_proof_ownership(t,s)
	_legacy_content(t,s)

func _capture(s: Dictionary) -> Dictionary:
	var a = s.pair.simulation
	return {"state":var_to_bytes(s.pair.state),"helper":a._streamed,"chunks":var_to_bytes(a._streamed._world._chunks),"helper_state":_helper_bytes(a._streamed),"world_status":var_to_bytes(a.world_status()),"query_status":var_to_bytes(a._streamed.query_status()),"attack_view":var_to_bytes(a._attack_view_cache),"pending":var_to_bytes(s.runtime._pending)}

func _helper_bytes(helper) -> PackedByteArray:
	return var_to_bytes({"identity":helper._prepared_identity,"hydration":helper._hydration,"blocked_routes":helper._blocked_routes,"props":helper._world._props,"buckets":helper._world._buckets,"dirty":helper._world._dirty,"collision_cache":helper._world._collision_bucket_cache,"clearance_cache":helper._world._clearance_cache,"coverage_cache":helper._world.coverage_cache_stats(),"navigation":helper._navigation.diagnostics(),"navigation_grids":helper._navigation._grids})

func _unchanged(t,s: Dictionary,before: Dictionary,label: String) -> void:
	var a = s.pair.simulation
	t.check(var_to_bytes(s.pair.state) == before.state,"rejected "+label+" preserves A's state and both RNG streams")
	t.check(a._streamed == before.helper and var_to_bytes(a._streamed._world._chunks) == before.chunks,"rejected "+label+" preserves A's helper and nested geometry")
	t.check(_helper_bytes(a._streamed) == before.helper_state,"rejected "+label+" preserves A's hydration, indexes and navigation/query caches")
	t.check(var_to_bytes(a.world_status()) == before.world_status and var_to_bytes(a._streamed.query_status()) == before.query_status,"rejected "+label+" preserves A's geometry/query status")
	t.check(var_to_bytes(a._attack_view_cache) == before.attack_view and var_to_bytes(s.runtime._pending) == before.pending,"rejected "+label+" preserves A's attack view and pending authority")

func _reject_like_cold(t,s: Dictionary,bad: Dictionary,label: String) -> void:
	var before := _capture(s)
	var input_bytes := var_to_bytes(bad)
	var cold: Dictionary = s.runtime.refresh_coverage(bad)
	t.check(not cold.get("ok",false),"cold oracle rejects "+label)
	var live: Dictionary = s.runtime.refresh_live_coverage(s.pair.simulation,bad)
	t.check(not live.get("ok",false),"live latest-snapshot admission rejects "+label)
	t.check(live.get("error_code") == cold.get("error_code"),"live rejection keeps cold error precedence for "+label+": "+str(live.get("error_code"))+" / "+str(cold.get("error_code")))
	t.check(not live.has("simulation") and not live.has("state"),"rejected "+label+" cannot publish a partial pair")
	t.check(var_to_bytes(bad) == input_bytes,"rejected "+label+" leaves caller-owned malformed input untouched")
	_unchanged(t,s,before,label)

func _dynamic_matrix(t,s: Dictionary) -> void:
	# A radius-only validator would accept these independent corruptions. A cold
	# oracle must reject first, so an accidentally valid fixture cannot pass.
	for field in ["unsupported_schema","schema_type","rules","config","config_identity","seal_ledger","kill_ledger","boss_ledger","reward_ledger","command_ledger","supply_ledger","progression_rng","offer","offer_queue","offer_queue_type","player_attack_type","enemy_attack_type","player_attack_record","enemy_attack_record","character_skill_type","character_skill_unowned","mobility_schema","mobility_phase","mobility_history","mobility_anchors","player_position","player_velocity","player_facing","player_hp","equipment","passives"]:
		var bad: Dictionary = s.pair.state.duplicate(true)
		match field:
			"unsupported_schema": bad.schema_version = 99
			"schema_type": bad.schema_version = "2"
			"rules": bad.rules.base_hp += 1
			"config": bad.run_config.doctrine_id = "missing_doctrine"
			"config_identity": bad.run_config.run_serial += 1
			"seal_ledger": bad.tactical_seals = 1
			"kill_ledger": bad.stats.kills = -1
			"boss_ledger": bad.boss_ids_fired = ["ch01_b05"]
			"reward_ledger": bad.reward_ids_claimed = ["boss:ch01_b05"]
			"command_ledger": bad.command_ids_applied = ["duplicate","duplicate"]
			"supply_ledger": bad.supply_used = true
			"progression_rng": bad.progression_rng_state = "+1"
			"offer": bad.upgrade_offer = {"source":"boss","options":[]}
			"offer_queue": bad.pending_offers = [{"source":"boss"}]
			"offer_queue_type": bad.pending_offers = [false]
			"player_attack_type": bad.player_attack_instances = {}
			"enemy_attack_type": bad.enemy_attack_instances = {}
			"player_attack_record": bad.player_attack_instances = [false]
			"enemy_attack_record": bad.enemy_attack_instances = [false]
			"character_skill_type": bad.character_skill = false
			"character_skill_unowned": bad.character_skill = {"ready_tick":0,"next_probe_tick":1,"pending_cast_id":""}
			"mobility_schema": bad.player_mobility.schema_version = "2"
			"mobility_phase": bad.player_mobility.phase = "airborne"
			"mobility_history": bad.player_mobility.hit_ids = ["same","same"]
			"mobility_anchors": bad.player_mobility.anchors = [false,false]
			"player_position": bad.player.position = [INF,192.0]
			"player_velocity": bad.player.velocity = ["0",0.0]
			"player_facing": bad.player.facing = [0.0,0.0]
			"player_hp": bad.player.hp = bad.player.max_hp+1
			"equipment": bad.equipment.blade_slash = 99
			"passives": bad.passives = {"unknown_passive":1}
		_reject_like_cold(t,s,bad,field)

func _boost_anchor_matrix(t,base: Dictionary) -> void:
	# Find a real production corridor, then let an actual Core tick create the
	# paired anchors. No hand-authored airborne record is used as the valid base.
	var state: Dictionary = base.runtime.new_run(base.chapter,Motion.seed_for_cast(),F.F.run_config())
	var first: Dictionary = base.runtime.refresh_coverage(state)
	t.check(first.get("ok",false),"anchor boundary fixture admits real production seed")
	if not first.get("ok",false): return
	var arranged := {}
	for chunk in first.simulation.world_render_view(first.state).get("chunks",[]):
		if chunk.chunk_id != "0,0": continue
		for left in chunk.props:
			for right in chunk.props:
				var a: Rect2 = left.ground_footprint
				var b: Rect2 = right.ground_footprint
				if a.position.x >= b.position.x or left.position.y != right.position.y: continue
				var gap: float = b.position.x-a.end.x
				if gap < 16.0 or gap >= 64.0: continue
				var approach := Vector2((a.end.x+b.position.x)*0.5,maxf(a.end.y,b.end.y)+16.0)
				if not first.simulation._streamed.walkable(approach,8.0).get("walkable",false): continue
				var candidate: Dictionary = first.state.duplicate(true)
				candidate.player.position = [approach.x,approach.y]
				if not Planner.plan(candidate,Vector2.UP,first.simulation._streamed).get("ok",false): continue
				arranged = candidate
				break
			if not arranged.is_empty(): break
		if not arranged.is_empty(): break
	t.check(not arranged.is_empty(),"anchor boundary fixture finds a genuine paired corridor")
	if arranged.is_empty(): return
	var pair: Dictionary = base.runtime.refresh_coverage(arranged)
	t.check(pair.get("ok",false),"anchor boundary fixture admits the arranged approach")
	if not pair.get("ok",false): return
	F.F.step(pair.simulation,pair.state,Vector2.UP)
	t.check(pair.simulation.step_status().get("ok",false) and pair.state.player_mobility.phase == "boost","anchor boundary fixture uses actual boost records")
	if pair.state.player_mobility.phase != "boost": return
	var s := base.duplicate(); s.pair = pair
	var valid: Dictionary = s.runtime.refresh_live_coverage(pair.simulation,pair.state)
	t.check(valid.get("ok",false),"uncorrupted actual boost remains admissible")
	for field in ["anchor_type","anchor_duplicate","anchor_revision_type","anchor_geometry_identity","anchor_chunk","anchor_local","path_revision","path_height","mobility_clock","mobility_hit_history"]:
		var bad: Dictionary = pair.state.duplicate(true)
		match field:
			"anchor_type": bad.player_mobility.anchors[0] = false
			"anchor_duplicate": bad.player_mobility.anchors[1] = bad.player_mobility.anchors[0].duplicate(true)
			"anchor_revision_type": bad.player_mobility.anchors[0].geometry_revision = false
			"anchor_geometry_identity":
				bad.player_mobility.anchors[0].geometry_revision = "0".repeat(64)
				var revision := Planner.pair_revision(bad.player_mobility.anchors)
				for point in bad.player_mobility.path: point.geometry_revision = revision
				bad.player_mobility.landing.geometry_revision = revision
				t.check(F.Core.Contracts.new().validate_snapshot(bad).is_empty(),"forged paired-anchor identity passes shape and reaches physical admission")
			"anchor_chunk": bad.player_mobility.anchors[0].chunk = ["01","0"]
			"anchor_local": bad.player_mobility.anchors[0].local = [INF,0.0]
			"path_revision": bad.player_mobility.path[0].geometry_revision = "0".repeat(64)
			"path_height": bad.player_mobility.path[0].height = 1.0
			"mobility_clock": bad.player_mobility.travel_ticks += 1
			"mobility_hit_history": bad.player_mobility.hit_ids = ["same","same"]
		_reject_like_cold(t,s,bad,field)

func _custom_callbacks(t,s: Dictionary) -> void:
	for kind in ["runtime","provider","disk"]:
		var provider = CallbackProvider.new() if kind == "provider" else s.provider
		var disk = CallbackDisk.new(s.directory.path_join("world")) if kind == "disk" else s.disk
		var runtime = CallbackRuntime.new(provider,disk) if kind == "runtime" else F.Runtime.new(provider,disk)
		var observed = runtime if kind == "runtime" else (provider if kind == "provider" else disk)
		observed.calls.clear()
		var cold: Dictionary = runtime.refresh_coverage(s.pair.state)
		var expected: Array = observed.calls.duplicate()
		t.check(cold.get("ok",false) and not expected.is_empty(),"custom "+kind+" cold oracle actually executes its extension callback")
		observed.calls.clear()
		var before := _capture(s)
		var live: Dictionary = runtime.refresh_live_coverage(s.pair.simulation,s.pair.state)
		t.check(live.get("ok",false) and cold.get("state") == live.get("state"),"custom "+kind+" uses successful unchanged cold admission")
		t.check(observed.calls == expected,"custom "+kind+" preserves exact original cold callback order/count")
		_unchanged(t,s,before,"custom "+kind+" fallback")

func _cold_preamble(t,s: Dictionary) -> void:
	var provider := SwitchProvider.new(s.chapter)
	var core := F.Core.new(provider)
	var need: Dictionary = F.H.requirements(s.pair.state)
	var hydration: Dictionary = s.disk.hydrate(s.pair.state.world.delta_root,need.chunks)
	t.check(hydration.get("ok",false) and core.restore(s.pair.state,hydration.get("deltas",{})).get("ok",false),"preamble oracle first admits unchanged real content")
	for mode in ["unavailable","changed"]:
		provider.blocked = mode == "unavailable"
		provider.chapter = s.chapter.duplicate(true)
		if mode == "changed": provider.chapter.content_fingerprint = "0".repeat(64)
		for field in ["unsupported_schema","schema_type","player_type"]:
			var bad: Dictionary = s.pair.state.duplicate(true)
			match field:
				"unsupported_schema": bad.schema_version = 99
				"schema_type": bad.schema_version = "2"
				"player_type": bad.player = false
			var reads := provider.reads
			var rejected: Dictionary = core.restore(bad,hydration.get("deltas",{}))
			# Exact dev9 classifies both unknown and wrong-type schema as
			# unsupported_schema, before attempting source acquisition.
			var expected := "unsupported_schema" if field in ["unsupported_schema","schema_type"] else "invalid_snapshot"
			t.check(rejected.get("error_code") == expected,"public cold "+field+" wins over "+mode+" content")
			t.check(provider.reads == reads,"public cold malformed preamble does not acquire "+mode+" content")
		var reads := provider.reads
		var valid_shape: Dictionary = core.restore(s.pair.state,hydration.get("deltas",{}))
		t.check(not valid_shape.get("ok",false) and provider.reads > reads,"valid cold shape still reads and rejects "+mode+" content")

func _legacy_content(t,s: Dictionary) -> void:
	var provider := F.City.new("dev4")
	var captured: Dictionary = provider.capture_validation_inputs()
	t.check(captured.get("ok",false),"dev4 cold fallback retains pinned source admission")
	if not captured.get("ok",false): return
	var parsed: Dictionary = provider.definitions_from_capture(captured)
	t.check(parsed.get("ok",false),"dev4 cold fallback retains pinned definitions")
	if not parsed.get("ok",false): return
	var core := F.Core.new(provider,null,parsed.definitions)
	var state: Dictionary = core.new_run(parsed.chapter,42,F.F.run_config())
	t.check(not state.has("error_code"),"dev4 cold fallback creates genuine legacy state")
	if state.has("error_code"): return
	var cold: Dictionary = s.runtime.refresh_coverage(state)
	t.check(cold.get("ok",false),"original cold Runtime accepts genuine dev4 world")
	if not cold.get("ok",false): return
	var legacy = s.runtime._content_router._legacy
	var prior_hits: Dictionary = legacy._proof_hits.duplicate(true)
	var live: Dictionary = s.runtime.refresh_live_coverage(cold.simulation,cold.state)
	t.check(live.get("ok",false) and live.get("state") == cold.state,"old content remains cold-compatible without identity rewriting")
	t.check(legacy._proof_hits != prior_hits,"old content cannot enter current live static proof lane")

func _proof_ownership(t,s: Dictionary) -> void:
	var a = s.pair.simulation
	t.check(a.has_method("_has_live_configuration"),"live eligibility has an owner-bound private proof check")
	if not a.has_method("_has_live_configuration"): return
	t.check(a._has_live_configuration(),"successful full prepared admission issues A's proof")
	var original: Variant = a._configuration_proof
	var other: Dictionary = s.runtime.refresh_coverage(s.pair.state)
	t.check(other.get("ok",false),"borrowed-proof fixture independently cold-admits another owner")
	if not other.get("ok",false): return
	for kind in ["dictionary","borrowed_owner"]:
		var before := _capture(s)
		# Even matching caller-supplied owner, nonce and validated-looking data
		# are not the private proof representation issued by this Core.
		if kind == "dictionary":
			a._configuration_proof = {"owner":weakref(a),"nonce":a._configuration_nonce,"data":original.data.duplicate(true),"trusted":true}
		else:
			a._configuration_proof = other.simulation._configuration_proof
		t.check(not a._has_live_configuration(),"external "+kind+" cannot forge live eligibility")
		t.check(a._fork_live_configuration() == null,"external "+kind+" cannot directly enter the configuration factory")
		var hits: Dictionary = s.provider._proof_hits.duplicate(true)
		var fallback: Dictionary = s.runtime.refresh_live_coverage(a,s.pair.state)
		t.check(fallback.get("ok",false) and fallback.get("state") == s.pair.state,"external "+kind+" retains valid original cold fallback")
		t.check(s.provider._proof_hits != hits,"external "+kind+" really executes cold source admission")
		_unchanged(t,s,before,"external "+kind)
		a._configuration_proof = original
	t.check(a._has_live_configuration(),"proof-forgery probes restore the original legitimate owner")
