extends RefCounted
# Public choice/step tests cover admission. These isolated executions use the
# real Core hit authority with authored records, without enemy movement masking
# exact circle/sector/capsule boundaries. No fake hit or geometry oracle is used.
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const IDS := ["evo_whirlwind","evo_sky_lance","evo_echo_assault","evo_wing_squad"]
func run(t) -> void:
	var catalog := Catalog.new()
	for id in IDS:
		var recipe: Dictionary = catalog.evolutions.definition(id)
		t.check(not recipe.is_empty(),"Core geometry family is registered: "+id)
		if recipe.is_empty(): continue
		for stage in 3: _stage_boundaries(t,recipe,id,stage)
func _stage_boundaries(t, recipe: Dictionary, id: String, stage: int) -> void:
	var geometry := {"bounds":[-2000,-2000,4000,4000],"obstacles":[]}
	var chapter := F.geometry_chapter(geometry,[0,0])
	var sim = F.geometry_sim(chapter)
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	t.check(not state.has("error_code"),"geometry Core uses current definitions: "+id)
	if state.has("error_code"): return
	state.equipment = {recipe.base_item_id:5}
	for required in recipe.get("required_equipment",[]): state.equipment[required.equipment_id] = int(required.level)
	for required in recipe.required_passives: state.passives[required.passive_id] = int(required.level)
	state.evolutions = {recipe.base_item_id:id}
	for base in state.equipment: state.player.attack_ready_ticks[base] = 2147483647
	var commands := []
	for index in 9: commands.append(F.spawn("boundary:"+str(index),[900+index*40,500],"brute"))
	F.step(sim,state,Vector2.ZERO,commands)
	t.check(state.entities.size() == 9,"boundary recipients are real spawned actors: "+id)
	if state.entities.size() != 9: return
	state.active_tick = 100
	state.survival_tick = 100
	var cast: String = state.run_id+":attack:1"
	var proposal: Dictionary = sim._evolved.reserve(state,recipe.base_item_id,Vector2(80,0),Vector2(1,0),cast)
	t.check(proposal.get("ok",false),"Core resolver authors boundary cast: "+id)
	if not proposal.get("ok",false): return
	var record: Dictionary = proposal.records[stage]
	var origin := Vector2(record.origin[0],record.origin[1])
	if id == "evo_whirlwind":
		state.player.position = [40.0,-20.0]
		origin = Vector2(40,-20)
	var direction := Vector2(record.direction[0],record.direction[1])
	var perpendicular := Vector2(-direction.y,direction.x)
	var body := float(state.entities[0].radius)
	var positions: Array[Vector2] = []
	var expected := ["boundary:0"]
	if record.shape == "line":
		var reach := float(record.length)
		var half := float(record.width)*0.5+body
		positions = [origin+direction*reach*0.5+perpendicular*(half-1.0),origin+direction*reach*0.5+perpendicular*(half+1.0),origin-direction*(half+2.0),origin+direction*(reach+half+2.0),origin+direction*reach*0.3,origin+direction*reach*0.7]
		expected.append_array(["boundary:4","boundary:5"])
	else:
		var reach := float(record.radius)
		positions = [origin+direction*(reach+body-1.0),origin+direction*(reach+body+1.0),origin-direction*reach*0.6,origin+direction.rotated(PI)*(reach+body+2.0),origin+Vector2(600,600),origin+Vector2(600,-600)]
		if record.shape == "circle": expected.append("boundary:2")
		if record.shape == "sector":
			var distance := reach*0.6
			var half_arc := deg_to_rad(float(record.arc_degrees)*0.5)
			var body_angle := asin(minf(0.99,body/distance))
			var margin := deg_to_rad(2.0)
			positions[4] = origin+direction.rotated(half_arc-body_angle-margin)*distance
			positions[5] = origin+direction.rotated(half_arc+body_angle+margin)*distance
			positions.append(origin+direction.rotated(-half_arc+body_angle+margin)*distance)
			positions.append(origin+direction.rotated(-half_arc-body_angle-margin)*distance)
			expected.append_array(["boundary:4","boundary:6","boundary:8"])
	if record.shape != "sector": positions.append_array([origin+Vector2(700,700),origin+Vector2(700,-700)])
	positions.append(Vector2(80,0) if id == "evo_echo_assault" else origin+Vector2(800,800))
	for index in positions.size():
		state.entities[index].position = [positions[index].x,positions[index].y]
		state.entities[index].hp = 1000.0
	state.attack_seq = 1
	# Earlier stages have already retired; this stage and every later reservation
	# are admitted together. Core executes just the stage due at this exact tick.
	state.player_attack_instances = proposal.records.filter(func(value): return int(value.stage_index) >= stage)
	state.active_tick = int(record.execute_tick)
	state.survival_tick = state.active_tick
	sim._spatial.rebuild(state.entities)
	var events: Array[Dictionary] = []
	var rewards: Array[Dictionary] = []
	sim._execute_player_attacks(state,events,rewards)
	var actual := []
	var seen := {}
	for event in events:
		if event.type != "damage": continue
		var key: String = str(event.payload.attack_id)+":"+str(event.payload.target_id)
		t.check(not seen.has(key),"each target is damaged once per executed stage: "+id)
		seen[key] = true
		actual.append(str(event.payload.target_id))
	actual.sort()
	expected.sort()
	t.check(actual == expected,"actual Core damage respects inside/outside, backward and far geometry at stage "+str(stage)+": "+id)
	if record.shape == "line": t.check(actual.has("boundary:4") and actual.has("boundary:5"),"authored line pierces both separate in-range actors: "+id)
	var executed := events.filter(func(event): return event.type == "player_attack" and event.payload.phase == "executed")
	t.check(executed.size() == 1 and executed[0].payload.stage_index == stage,"exactly the due stage executes and later stages wait: "+id)
	if id == "evo_whirlwind" and executed.size() == 1:
		t.check(executed[0].payload.origin == state.player.position and record.origin == [0.0,0.0],"expanded whirlwind follows the live player without rewriting the cast sample: "+id)
	var before := state.duplicate(true)
	events.clear()
	sim._execute_player_attacks(state,events,rewards)
	t.check(events.is_empty() and state == before,"executed stage cannot damage again on repeated resolution: "+id)
