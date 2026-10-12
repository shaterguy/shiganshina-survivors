extends RefCounted
var Core = load("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core/core_fixture.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Adapter = preload("res://game/app/world_checkpoint_adapter.gd")
class FixedProvider:
	extends RefCounted
	var chapter: Dictionary
	func _init(value: Dictionary) -> void: chapter = value.duplicate(true)
	func load_chapter(id: String) -> Dictionary:
		return {"ok":true,"chapter":chapter.duplicate(true)} if id == chapter.chapter_id else {"ok":false,"error_code":"unknown_chapter"}
class InvalidFreshHelper:
	extends "res://game/core/streamed_run_world.gd"
	var result: Variant
	func fresh(): return result
class AliasingHelper:
	extends "res://game/core/streamed_run_world.gd"
	func fresh(): return self
class EnvelopeProvider:
	extends RefCounted
	var value: Variant
	func _init(result: Variant) -> void: value = result
	func load_chapter(_id: String): return value
func run(t) -> void:
	var injected := false
	for method in Core.get_script_method_list():
		if method.name == "_init": injected = method.args.size() >= 2 and method.args[0].name == "chapter_provider" and method.args[1].name == "world_helper"
	t.check(injected,"C4 Core accepts explicit chapter provider and private helper dependencies")
	var finite_path := "res://tests/core/finite_chapter_provider.gd"
	t.check(FileAccess.file_exists(finite_path),"C4 has a frozen finite_test provider with a separate identity")
	if not injected or not FileAccess.file_exists(finite_path): return
	var finite = load(finite_path).new()
	var chapter: Dictionary = finite.load_chapter("chapter_01_shiganshina").chapter
	var production: Dictionary = City.new().load_chapter("chapter_01_shiganshina").chapter
	t.check(chapter.world_mode == "finite_test" and chapter.content_fingerprint != production.content_fingerprint,"finite and city rules have distinct explicit identities")
	var sim = Core.new(finite)
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	t.check(state.get("schema_version") == 2 and not state.has("world"),"injected finite provider constructs a finite run")
	if state.has("error_code"): return
	t.check(sim.restore(state).get("ok",false),"finite provider restores its own pinned run")
	t.check(not Core.new().restore(state).get("ok",false),"legacy default provider cannot reinterpret finite_test identity")
	t.check(not Core.new(City.new()).restore(state).get("ok",false),"city provider rejects a finite checkpoint")
	for path in ["data/equipment.json","data/passives.json","data/evolutions.json","data/doctrines.json","data/supply_shop.json"]:
		var changed := chapter.duplicate(true)
		changed.content_definition_hashes[path] = "0".repeat(64)
		var incompatible = Core.new(FixedProvider.new(changed))
		t.check(incompatible.new_run(changed,42,F.run_config()).get("error_code") == "content_mismatch","constructor blocks mixed gameplay definition: "+path)
		t.check(incompatible.restore(state).get("error_code") == "content_mismatch","restore blocks mixed gameplay definition: "+path)
	_provider_boundaries(t,chapter,production,state)
	_city(t,production)
func _city(t,chapter: Dictionary) -> void:
	var helper := Helper.new(chapter.world_definitions)
	var sim = Core.new(City.new(),helper)
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	t.check(state.get("world",{}).get("mode") == "streamed_city","real city constructor creates mandatory persistent world authority")
	if not state.has("world"): return
	t.check(state.rules.world_geometry.is_empty() and state.world.content_fingerprint == chapter.content_fingerprint,"city rules cannot silently contain finite geometry")
	t.check(helper.status().resident_chunks == 0,"constructor does not replace an injected live helper cache")
	var before := state.duplicate(true)
	var needed: Dictionary = Helper.requirements(state)
	t.check(needed.get("ok",false) and not needed.get("chunks",[]).is_empty(),"actual Core state yields real world coverage requirements")
	if not needed.get("ok",false): return
	var directory := "/tmp/c4_authority_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	var disk := Disk.new(directory)
	var staged: Dictionary = disk.prepare(state.world.delta_root,[],0)
	t.check(staged.ok,"exact world disk publishes the canonical initial empty root")
	if not staged.ok: return
	var hydration: Dictionary = disk.hydrate(state.world.delta_root,needed.chunks)
	t.check(hydration.ok and hydration.deltas.size() == needed.chunks.size(),"real verified hydration proves explicit absence for every required chunk")
	if not hydration.ok: return
	t.check(not sim.restore(state).get("ok",false),"missing hydration never becomes empty terrain")
	var restored: Dictionary = sim.restore(state,hydration.deltas)
	t.check(restored.get("ok",false) and restored.get("state") == state,"real city initial state passes Core restore")
	t.check(helper.status().resident_chunks == 0 and state == before,"restore uses fresh derived geometry and leaves live cache/state untouched")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
	var roundtrip: Dictionary = sim.restore(parsed,hydration.deltas)
	t.check(roundtrip.get("ok",false) and roundtrip.get("state") == state,"city initial authority survives full-precision disk JSON roundtrip")
	var prepared: Dictionary = sim.prepare_world(state,hydration.deltas)
	t.check(prepared.get("ok",false),"explicit prepare_world installs only a fully checked private candidate cache")
	var cache_before: Dictionary = sim.world_status()
	t.check(cache_before.get("resident_chunks",0) == needed.chunks.size(),"prepared Core owns the required generated chunk cache")
	var omitted: Dictionary = hydration.deltas.duplicate(true)
	omitted.erase(omitted.keys()[0])
	t.check(not sim.prepare_world(state,omitted).get("ok",false),"one missing hydrated key rejects preparation")
	t.check(sim.world_status() == cache_before and state == before,"failed B preparation preserves complete A cache and authority")
	for patch in [{"schema_version":2},{"mode":"unknown"},{"mode":{}},{"stage":false},{"content_fingerprint":"0".repeat(64)}]:
		var bad := state.duplicate(true)
		bad.world.merge(patch,true)
		t.check(not sim.restore(bad,hydration.deltas).get("ok",false),"present invalid world fails without finite fallback: "+str(patch))
		t.check(sim.world_status() == cache_before,"failed world validation cannot poison live cache")
	for bad_identity in [true,0,[],{},"",null]:
		var poisoned := state.duplicate(true)
		poisoned.rules.content_fingerprint = bad_identity
		t.check(sim.restore(poisoned,hydration.deltas).get("error_code") == "content_mismatch","rules fingerprint Variant is rejected: "+str(bad_identity))
	var absent := state.duplicate(true)
	absent.erase("world")
	t.check(not sim.restore(absent).get("ok",false),"streamed provider requires a world even with the correct fingerprint")
	var adapter := Adapter.new(Disk.new(directory),Callable(Helper,"requirements"),Callable(sim,"restore"))
	t.check(adapter.validate_checkpoint(parsed).get("ok",false),"exact adapter verifies disk closure then restores real city Core")
	var changed := state.duplicate(true)
	changed.rules.world_geometry = F.v2_chapter().world_geometry
	t.check(not sim.restore(changed,hydration.deltas).get("ok",false),"streamed fingerprint cannot authorize injected finite geometry")
	var idle := state.duplicate(true)
	F.step(sim,state,Vector2.RIGHT)
	t.check(state.active_tick == idle.active_tick+1,"C4b prepared city tick now advances through explicit geometry dispatch")

func _provider_boundaries(t,finite: Dictionary,city: Dictionary,state: Dictionary) -> void:
	for bad in [[],{},"yes",0,1,null]:
		var sim = Core.new(EnvelopeProvider.new({"ok":bad,"chapter":finite}))
		t.check(sim.new_run(finite,42,F.run_config()).get("error_code") == "content_mismatch","malformed provider success type fails explicitly: "+str(bad))
	for fingerprint in ["","x",[],{},true,null,"A".repeat(64),"g".repeat(64)]:
		var changed := finite.duplicate(true)
		changed.content_fingerprint = fingerprint
		var sim = Core.new(FixedProvider.new(changed))
		t.check(sim.new_run(changed,42,F.run_config()).get("error_code") == "content_mismatch","invalid provider fingerprint cannot construct authority: "+str(fingerprint))
		t.check(sim.restore(state).get("error_code") == "content_mismatch","invalid provider fingerprint cannot restore authority")
	var wrong: Dictionary = city.world_definitions.duplicate(true)
	for prop in wrong.props.definitions.values():
		if prop.destructible: prop.structure_hp += 17
	var helper := Helper.new(wrong)
	t.check(helper.valid(),"wrong-helper control is structurally valid but mechanically different")
	var sim = Core.new(City.new(),helper)
	t.check(sim.new_run(city,42,F.run_config()).get("error_code") == "content_mismatch","valid helper with different mechanics cannot impersonate provider fingerprint")
	var source: Dictionary = Core.new(City.new()).new_run(city,42,F.run_config())
	t.check(sim.restore(source,{}).get("error_code") == "content_mismatch","different helper definitions reject restore before missing hydration")
	var good := Helper.new(city.world_definitions)
	var bound = Core.new(City.new(),good)
	good._definitions.props.definitions.house_narrow.structure_hp += 1
	t.check(bound.new_run(city,42,F.run_config()).get("schema_version") == 2,"Core privately copies helper definitions against post-construction source mutation")

	var aliasing := AliasingHelper.new(city.world_definitions)
	var initial_hydration := {}
	for chunk in Helper.requirements(source).chunks: initial_hydration[chunk[0]+","+chunk[1]] = []
	t.check(aliasing.prepare(source,initial_hydration).get("ok",false),"self-alias control is an already prepared real helper")
	var prior: Dictionary = aliasing.render_view(source)
	var rejected = Core.new(City.new(),aliasing)
	t.check(rejected.new_run(city,42,F.run_config()).get("error_code") == "content_mismatch","self-aliasing fresh dependency is explicitly rejected")
	var bad := source.duplicate(true)
	bad.player.id = "bad"
	t.check(rejected.restore(bad,initial_hydration).get("error_code") == "content_mismatch" and aliasing.render_view(source) == prior,"rejected fresh alias cannot mutate caller live geometry")

	for result in [[],{},true,0,"bad",null]:
		var invalid_fresh := InvalidFreshHelper.new(city.world_definitions)
		invalid_fresh.result = result
		var refused = Core.new(City.new(),invalid_fresh)
		t.check(refused.new_run(city,42,F.run_config()).get("error_code") == "content_mismatch","invalid fresh result has an explicit envelope: "+str(result))

	var shape_patches := [{"chapter_id":"wrong"},{"chapter_id":{}},{"content_revision":"bad"},{"spawn_position":[]},{"spawn_position":[0]},{"spawn_position":["bad",0]},{"escape_zone":[]},{"escape_zone":null},{"enemy_catalog":[]},{"allowed_equipment_ids":[]},{"allowed_equipment_ids":["unknown"]},{"doctrine_ids":null},{"evolution_ids":true},{"enemy_ids":[]},{"boss_schedule":[]},{"world_geometry":[]}]
	for patch in shape_patches:
		var changed := finite.duplicate(true)
		changed.merge(patch,true)
		var malformed = Core.new(EnvelopeProvider.new({"ok":true,"chapter":changed}))
		t.check(malformed.new_run(changed,42,F.run_config()).get("error_code") == "content_mismatch","provider chapter malformed shape is rejected before typed use: "+str(patch))

	for weapons in [["wall_cannon"],["spin_slash"]]:
		var changed := finite.duplicate(true)
		changed.allowed_equipment_ids = weapons
		var crossref_core = Core.new(FixedProvider.new(changed))
		t.check(crossref_core.new_run(changed,42,F.run_config()).get("error_code") == "content_mismatch","declared doctrine/evolution weapons must be legal in the chapter")
