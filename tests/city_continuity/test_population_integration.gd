extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const C = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	_retire(t)
	_park(t)
	_xp_cap(t)
	_final_transition(t)
	_xp_overflow_rollback(t)
func _fixture(t) -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core := Core.new(provider)
	var state := core.new_run(chapter,42,C.run_config())
	state.player.position = [384.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":100000}
	var hydration := F.hydration(H.requirements(state))
	t.check(core.prepare_world(state,hydration).get("ok",false),"population fixture begins with a real prepared Core")
	return {"core":core,"state":state,"hydration":hydration,"chapter":chapter}
func _retire(t) -> void:
	var f := _fixture(t)
	var command := {"command_id":"far-walker","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"far-walker","enemy_id":"walker","position":[-1154.0,384.0],"spawned_tick":0}}
	var hydration := F.hydration(H.requirements(f.state,[command]))
	t.check(f.core.prepare_world(f.state,hydration,[command]).get("ok",false),"far ordinary spawn is backed by real geometry")
	C.step(f.core,f.state,Vector2.ZERO,[command])
	t.check(f.state.entities.size() == 1,"far ordinary control spawns through actual Core")
	var before: Dictionary = f.state.duplicate(true)
	C.step(f.core,f.state,Vector2.ZERO)
	t.check(f.state.active_tick == 2 and f.state.entities.is_empty(),"next quiescent tick retires an offscreen ordinary enemy")
	t.check(f.state.stats == before.stats and f.state.player.xp == before.player.xp and f.state.drops == before.drops and f.state.rng_state == before.rng_state and f.state.command_ids_applied == before.command_ids_applied,"retirement grants no kill, XP, drop, reward command or RNG draw")
	t.check(f.state.world.schema_version == 1,"ordinary retirement alone retains world-v1 authority")
func _park(t) -> Dictionary:
	var f := _fixture(t)
	f.state.active_tick = 17999
	f.state.survival_tick = 17999
	f.state.drops = [{"id":100,"position":[-1152.0,384.0],"xp":7}]
	f.state.next_entity_id = 101
	var command := {"command_id":"far-boss","kind":"spawn_boss","origin_revision":0,"payload":{"entity_id":"far-boss","enemy_id":"boss_charger","boss_id":"ch01_b05","position":[-1154.0,384.0],"scheduled_tick":18000}}
	var hydration := F.hydration(H.requirements(f.state,[command]))
	t.check(f.core.prepare_world(f.state,hydration,[command]).get("ok",false),"far boss and XP fixture are actual Core-valid")
	C.step(f.core,f.state,Vector2.ZERO,[command])
	C.step(f.core,f.state,Vector2.ZERO)
	t.check(f.core.step_status().get("ok",false) and f.state.world.schema_version == 2,"successful parking tick explicitly upgrades world schema")
	if f.state.world.schema_version != 2: return f
	t.check(f.state.world.dormant.entities.size() == 1 and f.state.world.dormant.drops.size() == 1 and f.state.entities.is_empty() and f.state.drops.is_empty(),"authored boss and XP remain bounded dormant records")
	t.check(f.state.world.dormant.entities[0].record.id == "far-boss" and f.state.world.dormant.drops[0].record.xp == 7,"parking preserves boss identity and all XP")
	var cold: Dictionary = f.core.restore(JSON.parse_string(JSON.stringify(f.state,"",true,true)),hydration)
	t.check(cold.get("ok",false) and cold.state == f.state,"world-v2 parked authority survives exact cold restore")
	var old: Dictionary = f.state.duplicate(true)
	old.world.schema_version = 3
	t.check(f.core.restore(old,hydration).get("error_code") == "unsupported_schema","future population authority fails closed")

	return f

func _xp_cap(t) -> void:
	var f := _fixture(t)
	f.state.active_tick = 18000
	f.state.survival_tick = 18000
	f.state.world.origin_chunk = ["9007199254740993","-9007199254740994"]
	f.state.world.schema_version = 2
	f.state.world.dormant = {"entities":[],"drops":[{"chunk":["9007199254740995","-9007199254740994"],"record":{"id":300,"position":[129.0,384.0],"xp":10}}]}
	f.state.drops = []
	for i in 255: f.state.drops.append({"id":i+1,"position":[-800.0,384.0],"xp":1})
	f.state.next_entity_id = 1000
	var hydration := F.hydration(H.requirements(f.state))
	t.check(f.core.prepare_world(f.state,hydration).get("ok",false),"256 global XP records at exact large chunk addresses are valid")
	var before: Dictionary = f.state.duplicate(true)
	var helper = f.core._streamed
	f.core._add_drop(f.state,[800.0,384.0],3)
	t.check(f.state.drops.size()+f.state.world.dormant.drops.size() == 256,"active and parked XP share one256-record cap")
	t.check(f.state.world.dormant.drops[0].record.xp == 13 and f.state.drops == before.drops,"overflow XP merges into the genuinely nearest absolute parked drop")
	t.check(f.state.world.dormant.drops[0].chunk == before.world.dormant.drops[0].chunk and f.state.world.dormant.drops[0].record.position == before.world.dormant.drops[0].record.position and f.state.world.dormant.drops[0].record.id == 300 and f.state.next_entity_id == before.next_entity_id,"XP merge preserves the existing target's absolute location, identity and allocator")
	t.check(f.core._streamed == helper and helper.matches(f.state),"population-only XP aggregation does not rebuild terrain identity")
	var total := 0
	for drop in f.state.drops: total += int(drop.xp)
	for entry in f.state.world.dormant.drops: total += int(entry.record.xp)
	t.check(total == 268,"all earned XP is conserved at the global cap")
	var invalid: Dictionary = before.duplicate(true)
	invalid.world.dormant.drops[0].chunk = ["-9223372036854775808","0"]
	t.check(not f.core.restore(invalid,hydration).get("ok",false),"impossible or overflowing dormant separation fails closed")

func _final_transition(t) -> void:
	var f := _park(t)
	f.state.active_tick = 107999
	f.state.survival_tick = 107999
	var command := {"command_id":"population-final","kind":"begin_evacuation","origin_revision":f.state.world.origin_revision,"payload":{"boss_id":"ch01_final_armored","escape_zone":[0,0,0,0],"evacuation_ticks":4500}}
	var events: Array = C.step(f.core,f.state,Vector2.ZERO,[command])
	t.check(f.state.phase == "evacuation" and f.state.final_started_tick == 108000 and "ch01_final_armored" in f.state.boss_ids_fired,"final armored remains a separate exactly-timed sixth threat")
	t.check(f.state.world.dormant.entities.is_empty() and f.state.world.dormant.drops.is_empty(),"explicit final scenario transition clears parked population alongside active city records")
	var phases := C.types(events,"phase_changed")
	t.check(phases.size() == 1 and phases[0].payload.get("population_cleared") == {"dormant_entities":1,"dormant_drops":1,"dormant_xp":7},"existing phase event accounts for the explicitly cleared dormant population")
	var repeat: Array = C.step(f.core,f.state,Vector2.ZERO,[command])
	t.check(C.types(repeat,"boss_spawned").is_empty() and C.types(repeat,"phase_changed").is_empty() and f.state.final_started_tick == 108000,"repeated final command cannot duplicate threat/event or reset timer")
	C.arrange_final_clock(f.state,112498)
	C.step(f.core,f.state,Vector2.ZERO)
	t.check(not f.state.evacuation_ready and f.state.phase == "evacuation","4499 final ticks remain insufficient with world-v2")
	C.step(f.core,f.state,Vector2.ZERO)
	t.check(f.state.evacuation_ready and f.state.phase == "evacuation" and f.state.escape_zone == [0.0,0.0,0.0,0.0],"4500 final ticks ready exactly once and city sentinel cannot auto-win")
	t.check(f.core.restore(JSON.parse_string(JSON.stringify(f.state,"",true,true)),f.hydration).get("ok",false),"post-final empty dormant world-v2 remains cold-restorable")

func _xp_overflow_rollback(t) -> void:
	var f := _fixture(t)
	f.state.world.schema_version = 2
	f.state.world.dormant = {"entities":[],"drops":[{"chunk":["2","0"],"record":{"id":300,"position":[384.0,384.0],"xp":2147483647}}]}
	f.state.next_entity_id = 301
	var command := {"command_id":"counter-victim","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"counter-victim","enemy_id":"walker","position":[445.0,384.0],"spawned_tick":0}}
	var hydration := F.hydration(H.requirements(f.state,[command]))
	t.check(f.core.prepare_world(f.state,hydration,[command]).get("ok",false),"bounded dormant XP counter fixture is valid")
	C.step(f.core,f.state,Vector2.ZERO,[command])
	t.check(f.state.entities.size() == 1,"overflow fixture uses a real living enemy")
	if f.state.entities.is_empty(): return
	f.state.entities[0].hp = 1.0
	f.state.player.attack_ready_ticks.blade_slash = f.state.active_tick
	# Put a legal record at the same target as the new kill. The next
	# actual damage/XP tick exceeds the signed counter on that active target.
	f.state.drops = [{"id":301,"position":[445.0,384.0],"xp":2147483647}]
	f.state.next_entity_id = 302
	var before: Dictionary = f.state.duplicate(true)
	var helper = f.core._streamed
	var events: Array = C.step(f.core,f.state,Vector2.ZERO)
	t.check(not f.core.step_status().get("ok",false) and events.is_empty(),"XP counter exhaustion refuses the actual killing tick")
	t.check(f.state == before and f.core._streamed == helper,"late XP refusal preserves live and dormant XP, damage, IDs, tick and helper")
