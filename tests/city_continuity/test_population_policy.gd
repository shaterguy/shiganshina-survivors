extends RefCounted
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func run(t) -> void:
	var path := "res://game/core/city_population.gd"
	t.check(FileAccess.file_exists(path),"bounded city population policy exists")
	if not FileAccess.file_exists(path): return
	var P = load(path)
	_transitions(t,P)
	var json_state := F.state(H.new(F.definitions()))
	for version in [1,2]:
		json_state.world.schema_version = version
		if version == 2: json_state.world.dormant = {"entities":[],"drops":[]}
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(json_state))
		t.check(H.validate_world(parsed).get("ok",false) and H.requirements(parsed).get("ok",false),"raw JSON schema float is valid before Core normalizes: "+str(version))
		parsed.world.schema_version = float(version)+0.25
		t.check(not H.validate_world(parsed).get("ok",false),"fractional world schema remains invalid")
	var state := F.state(H.new(F.definitions()))
	state.player.position = [384.0,384.0]
	state.entities = [{"id":1,"boss_id":"","position":[-1152.0,384.0],"action_state":"move"},{"id":2,"boss_id":"ch01_b05","position":[-1152.0,384.0],"action_state":"move"},{"id":3,"boss_id":"","position":[-1152.0,384.0],"action_state":"attack"}]
	state.drops = [{"id":4,"position":[384.0,1920.0],"xp":11}]
	var before := state.duplicate(true)
	var plan: Dictionary = P.plan(state)
	t.check(plan.get("ok",false) and plan.retire == [0] and plan.park_entities == [1] and plan.park_drops == [0],"exact exit boundary retires ordinary enemy and parks boss/XP only")
	t.check(state == before,"population planning is pure")
	state.entities[0].position[0] = -1151.99
	t.check(P.plan(state).retire.is_empty(),"entity inside exit threshold remains active")
	state.entities[0].position[0] = -1152.0
	state.telegraphs = [{"source_id":"1"}]
	t.check(P.plan(state).retire.is_empty(),"owned hazard prevents retirement even when action label is move")
	state.telegraphs = []
	state.world.schema_version = 2
	state.world.dormant = {"entities":[{"chunk":["2","0"],"record":{"id":5,"boss_id":"ch01_b10","position":[128.0,384.0],"action_state":"move"}}],"drops":[{"chunk":["2","0"],"record":{"id":6,"position":[128.01,384.0],"xp":9}}]}
	plan = P.plan(state)
	t.check(plan.wake_entities == [0] and plan.wake_drops.is_empty(),"wake boundary is inclusive at1280 and separated from1536 exit")
	var distance: Dictionary = P.distance_squared(["9007199254740993","-9007199254740994"],[0.25,0.5],["9007199254740994","-9007199254740994"],[0.25,0.5])
	t.check(distance.get("ok",false) and distance.value == 589824.0,"absolute distance subtracts integer chunks before conversion above2^53")
	t.check(not P.distance_squared(["-9223372036854775808","0"],[0,0],["9223372036854775807","0"],[0,0]).get("ok",true),"absolute distance rejects overflowing signed subtraction")
	t.check(not P.distance_squared(["0","0"],[NAN,0],["1","0"],[0,0]).get("ok",true),"absolute distance rejects nonfinite local coordinates")

func _transitions(t,P) -> void:
	var state := F.state(H.new(F.definitions()))
	state.player.position = [384.0,384.0]
	state.entities = [{"id":1,"boss_id":"","position":[-1152.0,384.0],"action_state":"move"}]
	var world_before: Dictionary = state.world.duplicate(true)
	t.check(P.has_method("apply_to_candidate"),"population transition API exists")
	if not P.has_method("apply_to_candidate"): return
	var retired: Dictionary = P.apply_to_candidate(state)
	t.check(retired.get("ok",false) and state.entities.is_empty() and state.world == world_before,"ordinary-only retirement does not invent a new persistence schema")
	state.entities = [{"id":2,"boss_id":"ch01_b05","position":[-1152.0,384.0],"action_state":"move","hp":19.0,"xp":17,"locked_origin":[-1152.0,384.0],"locked_target":[384.0,384.0]}]
	state.drops = [{"id":3,"position":[384.0,1920.0],"xp":11}]
	state.stats = {"kills":3,"damage_dealt":9.0,"minibosses_defeated":0}
	state.reward_ids_claimed = ["prior-reward"]
	state.rng_state = "123"
	var parked: Dictionary = P.apply_to_candidate(state)
	t.check(parked.get("ok",false) and state.world.schema_version == 2 and state.entities.is_empty() and state.drops.is_empty(),"first actual parking upgrades only the candidate world to schema2")
	t.check(state.world.dormant.entities[0].chunk == ["-2","0"] and state.world.dormant.entities[0].record.position == [384.0,384.0],"boss parking preserves the exact absolute address")
	t.check(state.world.dormant.drops[0].chunk == ["0","2"] and state.world.dormant.drops[0].record == {"id":3,"position":[384.0,384.0],"xp":11},"XP parking preserves record ID, amount and absolute position")
	t.check(state.stats == {"kills":3,"damage_dealt":9.0,"minibosses_defeated":0} and state.reward_ids_claimed == ["prior-reward"] and state.rng_state == "123","parking grants no kills, reward, XP or RNG advancement")
	state.player.position = [-128.0,384.0]
	var woke: Dictionary = P.apply_to_candidate(state)
	t.check(woke.get("ok",false) and state.entities.size() == 1 and state.entities[0].id == 2 and state.entities[0].position == [-1152.0,384.0] and state.entities[0].hp == 19.0,"boss re-entry restores its original physical position, identity and HP")
	t.check(state.world.schema_version == 2 and state.world.dormant.entities.is_empty() and state.world.dormant.drops.size() == 1,"empty boss dormancy does not downgrade schema or discard distant XP")
