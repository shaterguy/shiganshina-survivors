extends RefCounted
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const A = preload("res://game/world/world_address.gd")
# These are world-query fixtures, not full Core snapshots. Performance RED is
# the separately frozen actual-Core readiness benchmark; no flaky time asserts.
func run(t) -> void:
	var helper := H.new(F.definitions())
	var source := F.state(helper)
	var actor := {"position":[500,384],"locked_origin":[500,384],"locked_target":[384,384],"radius":18,"speed":28,"geometry":{"origin":[500,384],"target":[384,384],"radius":32}}
	for origin in [["0","0"],["9007199254740993","-9007199254740994"],["-41","83"]]:
		var state := source.duplicate(true)
		state.world.origin_chunk = origin.duplicate()
		var base := H.requirements(state)
		var expected := []
		for y in range(-1,2):
			for x in range(-1,2): expected.append([str(A.add(origin[0].to_int(),x).value),str(A.add(origin[1].to_int(),y).value)])
		t.check(base.ok and base.chunks == expected,"exact ordered nine-cell coverage at full-precision origin "+str(origin))
		for count in [1,50,200,512]:
			state.entities.clear()
			for i in count: state.entities.append(actor.duplicate(true))
			var before := state.duplicate(true)
			t.check(H.requirements(state) == base and state == before,"repeated actor cells are a pure set union: "+str(count))
			state.entities[-1].locked_target = [5000,384]
			t.check(H.requirements(state).get("error_code") == "outside_working_set","late out-of-window field is never hidden by earlier duplicate cells")
			state.entities[-1] = actor.duplicate(true)
			state.entities[-1].geometry.radius = NAN
			t.check(H.requirements(state).get("error_code") == "invalid_snapshot","late invalid geometry is validated despite repeated cells")
		state.entities = [actor.duplicate(true)]
		state.entities[0].position = [2304,384]
		state.entities[0].locked_origin = [2304,384]
		var wider := H.requirements(state)
		t.check(wider.ok and wider.chunks.size() > base.chunks.size(),"a later call computes newly required cells rather than retaining an old set")
		state.entities = []
		t.check(H.requirements(state) == base,"a following smaller call is independent of prior expanded coverage")
	var state := source.duplicate(true)
	var required := H.requirements(state)
	var missing := helper.readiness(state)
	var keys := []
	for chunk in required.chunks: keys.append(A.key(chunk))
	t.check(not missing.ok and missing.missing_delta_keys == keys,"unprepared readiness lists every exact required absolute key")
	t.check(helper.prepare(state,F.hydration(required)).ok and helper.readiness(state).ok,"prepared identity admits the same required cells")
	var view := helper.render_view(state)
	var changed := state.duplicate(true)
	changed.world.world_revision = 1
	var mismatch := helper.readiness(changed)
	t.check(not mismatch.ok and mismatch.missing_delta_keys == keys and helper.render_view(state) == view,"new world identity rejects every cached key without altering prior cache")
	var stale := {"kind":"spawn_enemy","origin_revision":1,"payload":{"position":[384,384]}}
	t.check(helper.readiness(state,[stale]).get("error_code") == "stale_origin_revision","readiness keeps command validation before cache lookup")
	for value in [NAN,INF,-INF,1e100,true,"384",[],{}]:
		var hostile := state.duplicate(true)
		hostile.entities = [actor.duplicate(true),actor.duplicate(true)]
		hostile.entities[-1].position = [value,384]
		t.check(H.requirements(hostile).get("ok",true) == false,"every repeated-cell record still validates hostile coordinate "+str(value))
