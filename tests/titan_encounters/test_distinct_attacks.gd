extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
class GeometryProvider:
	extends RefCounted
	var chapter: Dictionary
	func _init(world: Dictionary) -> void:
		chapter = F.v2_chapter()
		chapter.world_geometry = world
		chapter.content_identity_kind = "titan_encounter_geometry_fixture"
		chapter.content_fingerprint = load("res://game/director/chapter_catalog.gd").new().definition_digest(chapter)
	func load_chapter(_id: String) -> Dictionary:
		return {"ok":true,"chapter":chapter.duplicate(true)}
const Model = preload("res://game/combat/enemy_attack_model.gd")
const Roles = preload("res://game/combat/enemy_role_catalog.gd")
func run(t) -> void:
	var catalog: Dictionary = Roles.read().get("catalog",{})
	for id in ["quadruped","stone_thrower"]:
		t.check(catalog.get("roles",{}).has(id),"distinct role profile exists: "+id)
		if not catalog.get("roles",{}).has(id): continue
		_lifecycle(t,id,catalog)
		_evasion(t,id)
		_wall(t,id)
	_director(t)
func _lifecycle(t,id: String,catalog: Dictionary) -> void:
	var f := G.setup()
	var sim = f.sim
	var state: Dictionary = f.state
	var point := [140.0,0.0] if id == "quadruped" else [240.0,0.0]
	F.step(sim,state,Vector2.ZERO,[G.spawn(71,point,id)])
	t.check(state.enemy_attack_instances.size() == 1,"actual spawn owns distinct attack: "+id)
	if state.enemy_attack_instances.is_empty(): return
	var attack: Dictionary = state.enemy_attack_instances[0].duplicate(true)
	var profile: Dictionary = catalog.roles[id].profile
	var hit := 0
	var phases := {}
	var saw_projectile := false
	for tick in range(2,int(attack.recover_ends_tick)+1):
		var events := F.step(sim,state,Vector2.ZERO)
		hit += F.types(events,"damage").size()
		var actor: Dictionary = state.entities[0]
		phases[actor.action_state] = true
		var view: Dictionary = sim.enemy_attack_view(state)
		for entry in view.get("attacks",[]):
			if entry.get("projectile_pose",{}).get("visible",false): saw_projectile = true
		if tick in [attack.active_from_tick-1,attack.active_from_tick,attack.attack_ends_tick-1,attack.attack_ends_tick,attack.recover_ends_tick-1,attack.recover_ends_tick]:
			var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
			t.check(restored.get("ok",false) and restored.get("state",{}) == state,"JSON restore keeps actual attack boundary "+id+":"+str(tick))
	t.check(phases.has_all(["windup","attack","recover","move"]),"complete W/A/R loop: "+id)
	t.check(hit == 1 and state.player.hp == state.player.max_hp-float(catalog.roles[id].definition.damage),"one actual damage hit per distinct attack: "+id)
	t.check(state.telegraphs.is_empty() and state.enemy_attack_instances.is_empty(),"single damage owner and finished cleanup: "+id)
	if id == "quadruped": t.check(state.entities[0].position != point,"quadruped body actually rushes")
	else: t.check(state.entities[0].position == point and saw_projectile,"thrower stays planted while a separate rock travels")
func _evasion(t,id: String) -> void:
	var f := G.setup()
	var state: Dictionary = f.state
	F.step(f.sim,state,Vector2.ZERO,[G.spawn(71,[140.0,0.0] if id == "quadruped" else [240.0,0.0],id)])
	if state.enemy_attack_instances.is_empty(): return
	var end := int(state.enemy_attack_instances[0].recover_ends_tick)
	for tick in range(2,end): F.step(f.sim,state,Vector2.DOWN if tick < 32 else Vector2.ZERO)
	t.check(state.player.hp == state.player.max_hp,"locked heading can be evaded sideways: "+id)
func _wall(t,id: String) -> void:
	var provider := GeometryProvider.new({"bounds":[-500,-500,1000,1000],"obstacles":[[-30,-120,20,240]]})
	var sim = load("res://game/core/run_simulation.gd").new(provider)
	var state: Dictionary = sim.new_run(provider.chapter,42,F.run_config())
	t.check(not state.has("error_code"),"wall fixture constructs valid current content: "+id)
	if state.has("error_code"): return
	state.player.attack_ready_ticks = {"blade_slash":2147483647}
	F.step(sim,state,Vector2.ZERO,[G.spawn(71,[-140.0,0.0] if id == "quadruped" else [-240.0,0.0],id)])
	t.check(state.enemy_attack_instances.size() == 1,"wall encounter is admitted with a safe player path: "+id)
	if state.enemy_attack_instances.is_empty(): return
	var a: Dictionary = state.enemy_attack_instances[0].duplicate(true)
	var saw_block := false
	for tick in range(2,int(a.recover_ends_tick)):
		F.step(sim,state,Vector2.ZERO)
		if id == "stone_thrower":
			for entry in sim.enemy_attack_view(state).get("attacks",[]): saw_block = saw_block or entry.get("projectile_pose",{}).get("blocked",false)
	t.check(state.player.hp == state.player.max_hp,"actual solid blocks damage: "+id)
	if id == "quadruped": t.check(float(state.entities[0].position[0]) <= -48.0,"quadruped body does not cross wall")
	else: t.check(saw_block,"rock expires on swept wall impact")
func _director(t) -> void:
	var f := G.setup()
	var director = load("res://game/director/spawn_director.gd").new()
	var seen := {}
	var chapter := F.v2_chapter()
	for tick in range(3500,8300):
		f.state.active_tick = tick; f.state.survival_tick = tick
		for c in director.plan(f.state,chapter):
			if c.kind == "spawn_enemy": seen[c.payload.enemy_id] = true
	t.check(seen.has("quadruped") and seen.has("stone_thrower"),"production Director actually schedules both new roles")

	f.state.active_tick = 90029; f.state.survival_tick = 90029
	var specials := 0
	for c in director.plan(f.state,chapter):
		if c.kind == "spawn_enemy" and c.payload.enemy_id in ["quadruped","stone_thrower"]: specials += 1
	t.check(specials <= 1,"late dense waves preserve one new-special slot rather than duplicating extensions through legacy roster")
