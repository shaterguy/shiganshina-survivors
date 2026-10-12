extends RefCounted
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
func run(t) -> void:
	var chapter: Dictionary = load("res://game/director/chapter_catalog.gd").new().load_chapter("chapter_01_shiganshina").chapter
	var sim = load("res://game/core/run_simulation.gd").new()
	var commands: Array[Dictionary] = []
	for direction in [Vector2.RIGHT,Vector2.DOWN,Vector2.UP]:
		var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
		for tick in range(600): sim.step(state,direction,commands)
		var pos := Vector2(state.player.position[0],state.player.position[1])
		t.check(pos.x <= 632 and pos.y <= 408 and pos.y >= -292,"city movement cannot escape walls or river")
	var path := "res://game/combat/world_geometry.gd"
	t.check(FileAccess.file_exists(path),"world collision geometry exists")
	if not FileAccess.file_exists(path): return
	var geometry = load(path).new()
	var world := {"bounds":[-640,-300,1280,716],"obstacles":[[-40,-80,80,40]]}
	t.check(not geometry.walkable(Vector2(0,-60),8,world),"solid house footprint blocks movement")
	var moved: Vector2 = geometry.move(Vector2(-60,-60),Vector2(40,12),8,world)
	t.check(moved.x <= -48 and moved.y > -60,"movement slides along solid footprint")
	t.check(geometry.walkable(moved,8,world),"sliding never enters solid footprint")
	_test_geometry(t,geometry)
	_test_world_snapshots(t,sim,chapter,geometry)
	_test_navigation(t,sim,geometry)
	_test_locked_attacks(t,sim,geometry)
	_test_charge_capsules(t,sim)
	_test_city_routes(t,geometry)
	_test_boundary_spawn_clearance(t,sim)
func _test_geometry(t,g) -> void:
	var world := {"bounds":[-640,-300,1280,716],"obstacles":[[-40,-80,80,40]]}
	for point in [Vector2(-632,-292),Vector2(632,408),Vector2(-48,-60),Vector2(0,-88)]:
		t.check(g.walkable(point,8,world),"exact outer/solid tangency is walkable")
	for point in [Vector2(-632.01,0),Vector2(0,408.01),Vector2(-47.99,-60),Vector2(0,-87.99)]:
		t.check(not g.walkable(point,8,world),"tiny intrusion beyond exact edge is blocked")
	for delta in [Vector2(10000,0),Vector2(-10000,0),Vector2(0,10000),Vector2(0,-10000),Vector2(10000,10000)]:
		var end: Vector2 = g.move(Vector2.ZERO,delta,8,world)
		t.check(g.walkable(end,8,world),"large upgraded displacement cannot tunnel or leave bounds")
	var corner: Vector2 = g.move(Vector2(-60,-100),Vector2(40,40),8,world)
	t.check(g.walkable(corner,8,world),"diagonal corner collision is solid")
	var stopped: Vector2 = g.sweep(Vector2(-80,-60),Vector2(200,0),8,world)
	t.check(stopped == Vector2(-48,-60),"straight sweep stops at first solid without tunneling")
	t.check(g.valid(world) and g.valid({}),"bounded and legacy empty geometry validate")
	for bad in [{"bounds":[0,0,0,30],"obstacles":[]},{"bounds":[0,0,30,30],"obstacles":[[29,0,5,5]]},{"bounds":[0,0,30,30],"obstacles":[[1,1,-1,2]]},{"bounds":[0,0,30,30]}, {"bounds":"bad","obstacles":[]}]:
		t.check(not g.valid(bad),"malformed or out-of-bounds geometry rejected")
func _test_world_snapshots(t,sim,chapter: Dictionary,g) -> void:
	t.check(chapter.content_revision == "ch01.3-rebuild.7-grabber-hand" and chapter.has("world_geometry"),"current authored revision loads collision geometry")
	var state: Dictionary = sim.new_run(chapter,1,Fixture.run_config())
	t.check(state.rules.has("world_geometry"),"snapshot captures exact chapter geometry")
	if not state.rules.has("world_geometry"): return
	var raw: Dictionary = JSON.parse_string(JSON.stringify(sim.snapshot(state),"",true,true))
	var result: Dictionary = sim.restore(raw)
	t.check(result.ok and result.state == state,"city checkpoint JSON roundtrip is exact")
	var broken := raw.duplicate(true)
	broken.rules.erase("world_geometry")
	t.check(not sim.restore(broken).ok,"new city checkpoint cannot silently lose world rules")
	broken = raw.duplicate(true)
	broken.rules.world_geometry.obstacles = [[0,0,-5,10]]
	t.check(not sim.restore(broken).ok,"invalid world snapshot rejected")
	broken = raw.duplicate(true)
	broken.player.position = [0,500]
	var copy := broken.duplicate(true)
	t.check(not sim.restore(broken).ok and broken == copy,"out-of-bounds checkpoint rejected without mutation")
	var world: Dictionary = chapter.world_geometry
	for point in [Vector2(-632,-292),Vector2(632,-292),Vector2(-632,408),Vector2(632,408)]:
		var position: Vector2 = point
		for tick in 1500:
			var direction: Vector2 = g.direction(position,Vector2(0,360),8,world)
			position = g.move(position,direction*2.0,8,world)
			if position.distance_to(Vector2(0,360)) < 2: break
		t.check(position.distance_to(Vector2(0,360)) < 2,"exit reachable from each city corner")
func _chapter() -> Dictionary:
	return Fixture.geometry_chapter({"bounds":[-300,-240,600,600],"obstacles":[[-40,-100,80,200]]})
func _test_navigation(t,sim,g) -> void:
	sim = Fixture.geometry_sim(_chapter())
	var fixture = load("res://tests/core/new_current_regression_fixture.gd")
	var state: Dictionary = sim.new_run(_chapter(),1,Fixture.run_config())
	state.equipment.clear()
	state.player.invulnerable_until = 200000
	fixture.step(sim,state,Vector2.ZERO,[fixture.spawn("walker",[-150,0],"walker")])
	var always_walkable := true
	for tick in 1600:
		fixture.step(sim,state,Vector2.ZERO,[])
		always_walkable = always_walkable and g.walkable(Vector2(state.entities[0].position[0],state.entities[0].position[1]),18,state.rules.world_geometry)
	t.check(always_walkable,"normal enemy never walks through house during detour")
	t.check(Vector2(state.entities[0].position[0],state.entities[0].position[1]).distance_to(Vector2(150,0)) < 25,"normal enemy routes around house without a symmetric deadlock")
	for point in [[-1000,0],[1000,500],[0,0]]:
		var spawned: Dictionary = sim.new_run(_chapter(),1,Fixture.run_config())
		fixture.step(sim,spawned,Vector2.ZERO,[fixture.spawn("outside",point,"walker")])
		t.check(spawned.entities.size() == 1 and g.walkable(Vector2(spawned.entities[0].position[0],spawned.entities[0].position[1]),18,spawned.rules.world_geometry),"outside or solid spawn is relocated walkably")
func _test_locked_attacks(t,sim,g) -> void:
	var fixture = load("res://tests/core/new_current_regression_fixture.gd")
	for enemy_id in ["boss_charger","boss_grabber","boss_leaper"]:
		var chapter := _chapter()
		chapter = Fixture.geometry_chapter(chapter.world_geometry,[285,0] if enemy_id == "boss_leaper" else [100,0])
		sim = Fixture.geometry_sim(chapter)
		var state: Dictionary = sim.new_run(chapter,2,Fixture.run_config())
		state.equipment.clear()
		state.player.invulnerable_until = 200000
		fixture.step(sim,state,Vector2.ZERO,[Fixture.actor_command(state,enemy_id,[-150,0])])
		var valid := true
		var landed := false
		for tick in 210:
			var actor: Dictionary = state.entities[0]
			if actor.action_state != "airborne":
				valid = valid and g.walkable(Vector2(actor.position[0],actor.position[1]),actor.radius,state.rules.world_geometry)
			if enemy_id == "boss_leaper" and actor.action_state == "attack": landed = true
			var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
			valid = valid and restored.ok
			if restored.ok:
				valid = valid and restored.state == state
				fixture.step(sim,restored.state,Vector2.ZERO,[])
			fixture.step(sim,state,Vector2.ZERO,[])
			if restored.ok: valid = valid and restored.state == state
		t.check(valid,"blocked rush and legal leap phase snapshots exactly replay: "+enemy_id)
		if enemy_id == "boss_leaper": t.check(landed,"leaper reaches walkable landing near player at boundary")

func _test_charge_capsules(t,sim) -> void:
	var fixture = load("res://tests/core/new_current_regression_fixture.gd")
	var attack = load("res://game/combat/attack_geometry.gd")
	for enemy_id in ["runner","grabber","boss_charger","boss_grabber","boss_abnormal"]:
		var chapter := _chapter()
		chapter = Fixture.geometry_chapter(chapter.world_geometry,[100,80])
		sim = Fixture.geometry_sim(chapter)
		var state: Dictionary = sim.new_run(chapter,2,Fixture.run_config())
		state.equipment.clear()
		state.player.invulnerable_until = 200000
		fixture.step(sim,state,Vector2.ZERO,[Fixture.actor_command(state,enemy_id,[-110,-60])])
		var covered := true
		var samples := 0
		for tick in 1200:
			var actor: Dictionary = state.entities[0]
			if actor.action_state == "attack" and actor.attack_kind in ["charge","grab"]:
				samples += 1
				var center := Vector2(actor.position[0],actor.position[1])
				if enemy_id == "grabber":
					covered = covered and actor.position == actor.locked_origin and state.telegraphs.is_empty()
				else:
					for index in 16:
						var edge := center+Vector2.from_angle(TAU*index/16.0)*float(actor.radius)
						# Perimeter samples allow only 0.001 world units of float32 rounding.
						covered = covered and attack.overlaps(state.telegraphs[0],edge,0.001)
				var corrupted := state.duplicate(true)
				corrupted.entities[0].position[1] += 5
				var unchanged := corrupted.duplicate(true)
				covered = covered and not sim.restore(corrupted).ok and corrupted == unchanged
			fixture.step(sim,state,Vector2.ZERO,[])
		t.check(samples > 0 and covered,"blocked diagonal rush remains inside actual capsule and rejects displaced actor: "+enemy_id)
	sim = Fixture.geometry_sim(_chapter())
	var leap: Dictionary = sim.new_run(_chapter(),1,Fixture.run_config())
	leap.equipment.clear()
	fixture.step(sim,leap,Vector2.ZERO,[Fixture.actor_command(leap,"boss_leaper",[-150,0],"leaper")])
	leap.entities[0].locked_target = [0,0]
	leap.telegraphs[0].origin = [0,0]
	t.check(not sim.restore(leap).ok,"leap landing inside solid rejected even when warning agrees")
func _test_city_routes(t,g) -> void:
	var world: Dictionary = load("res://game/director/chapter_catalog.gd").new().load_chapter("chapter_01_shiganshina").chapter.world_geometry
	for radius in [8.0,16.0,18.0,20.0,24.0,28.0,30.0,32.0]:
		for start in [Vector2(-600,-260),Vector2(600,-260),Vector2(-600,375),Vector2(600,375)]:
			var position: Vector2 = g.nearest_walkable(start,radius,world)
			var valid := true
			for tick in 1600:
				position = g.move(position,g.direction(position,Vector2(0,360),radius,world)*2.0,radius,world)
				valid = valid and g.walkable(position,radius,world)
				if position.distance_to(Vector2(0,360)) < 2: break
			t.check(valid and position.distance_to(Vector2(0,360)) < 2,"all body sizes route from city extremes to dock")
	for point in [Vector2(-56,320),Vector2(56,320),Vector2(-56,400),Vector2(56,400)]:
		t.check(g.walkable(point,8,world),"every escape rectangle corner is accessible to player")

func _test_boundary_spawn_clearance(t,sim) -> void:
	var fixture = load("res://tests/core/new_current_regression_fixture.gd")
	var chapter: Dictionary = load("res://game/director/chapter_catalog.gd").new().load_chapter("chapter_01_shiganshina").chapter
	var state: Dictionary = sim.new_run(chapter,1,Fixture.run_config())
	state.player.position = [632,0]
	state.equipment.clear()
	fixture.step(sim,state,Vector2.ZERO,[fixture.spawn("outside",[952,0],"walker")])
	var actor: Dictionary = state.entities[0]
	var distance := Vector2(actor.position[0],actor.position[1]).distance_to(Vector2(632,0))
	t.check(distance >= 120 and state.player.hp == state.player.max_hp,"outward border spawn relocates safely instead of appearing on player")
	var replay: Dictionary = sim.new_run(chapter,1,Fixture.run_config())
	replay.player.position = [632,0]
	replay.equipment.clear()
	fixture.step(sim,replay,Vector2.ZERO,[fixture.spawn("outside",[952,0],"walker")])
	t.check(replay == state,"safe spawn relocation is deterministic and consumes no RNG")
