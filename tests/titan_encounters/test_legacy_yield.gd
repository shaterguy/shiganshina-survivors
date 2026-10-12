extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
func run(t) -> void:
	var f := G.setup()
	var sim = f.sim
	var state: Dictionary = f.state
	F.step(sim,state,Vector2.ZERO,[G.spawn(7,[170.0,0.0])])
	t.check(state.enemy_attack_instances.size() == 1,"fixture owns an accepted role attack")
	F.step(sim,state,Vector2.ZERO,[G.spawn(99,[-170.0,0.0],"runner")])
	t.check(state.telegraphs.is_empty(),"new legacy windup cannot steal an already reserved early role slot")
	var continued := false
	for tick in range(3,100):
		F.step(sim,state,Vector2.ZERO)
		continued = continued or not state.telegraphs.is_empty()
	t.check(continued,"legacy attack resumes after existing role danger ends")
	f = G.setup(); sim = f.sim; state = f.state
	F.step(sim,state,Vector2.ZERO,[G.spawn(7,[170.0,0.0]),G.spawn(99,[-170.0,0.0],"runner")])
	var role_seen := false
	for tick in range(2,170):
		F.step(sim,state,Vector2.ZERO)
		role_seen = role_seen or not state.enemy_attack_instances.is_empty()
	t.check(role_seen,"legacy-first mixed encounter eventually admits waiting grabber")

	f = G.setup(); sim = f.sim; state = f.state
	F.step(sim,state,Vector2.ZERO,[G.spawn(7,[170.0,0.0]),G.spawn(8,[20.0,0.0],"walker"),G.spawn(99,[-170.0,0.0],"runner")])
	for tick in range(2,242):
		F.step(sim,state,Vector2.ZERO)
	t.check(state.entities[2].pattern_index >= 2,"geometry-blocked role cannot permanently freeze repeated legacy attacks")

	# Multiple staggered rejected waiters must share one yield window. Per-actor
	# windows can otherwise tile all 120 ticks and starve legacy forever.
	f = G.setup(); sim = f.sim; state = f.state
	for offset in [0,30,60,90]:
		state.entities.append({"enemy_id":"grabber","hp":80.0,"action_state":"move","role_wait_since":offset})
	var legacy_opportunities := 0
	for tick in range(240,360):
		state.active_tick = tick
		state.survival_tick = tick
		if sim._legacy_role_slot_available(state,{}): legacy_opportunities += 1
	t.check(legacy_opportunities == 90,"staggered rejected waiters leave a shared 90-of-120 legacy opportunity")
