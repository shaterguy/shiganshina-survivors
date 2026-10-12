extends RefCounted
const PATH := "res://game/presentation/combat_vfx_director.gd"
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
# Catch replayed casts, damage-as-cast, late crossfire flight, wrong origin,
# stale restored contact, wall-clock aging, rebase jumps and unbounded metadata.
func run(t) -> void:
	t.check(FileAccess.file_exists(PATH), "combat VFX director exists")
	if not FileAccess.file_exists(PATH): return
	var script = load(PATH)
	t.check(script != null and script.can_instantiate(), "combat VFX director loads")
	if script == null or not script.can_instantiate(): return
	var d = script.new()
	d.reset("run")
	var s := snapshot(10)
	var event := attack(1,"blade_slash","",10,10,"executed",{"shape":"sector","origin":[0,0],"direction":[1,0],"radius":54,"arc_degrees":150})
	var events: Array[Dictionary] = [event]
	var original := events.duplicate(true)
	d.consume(events,s)
	d.consume(events,s)
	t.check(d.present(s).size() == 1, "same player attack consumed twice emits one cast")
	t.check(events == original, "event inputs are immutable")
	var presented: Array[Dictionary] = d.present(s)
	presented[0].geometry.radius = 1000
	t.check(d.present(s)[0].geometry.radius == 54, "present output is deep-copied")
	t.check(d.present(snapshot(10)).size() == 1, "pause freezes effect on active tick")
	t.check(d.present(snapshot(20)).is_empty(), "ten-tick effect expires at its exclusive end")
	d.reset("run")
	d.consume(_events([{"event_id":"run:1","tick":10,"type":"damage","payload":{"target_id":2,"amount":10,"position":[4,5],"item_id":"blade_slash"}}]),s)
	t.check(_count(d.present(s),"cast") == 0, "damage alone never creates player cast")
	d.reset("run")
	d.consume(_events([event]),s)
	t.check(_count(d.present(s),"cast") == 1 and _count(d.present(s),"impact") == 0, "miss preserves cast without impact")
	d.reset("run")
	var launch := attack(1,"wall_cannon","",10,10,"executed",{"shape":"projectile","origin":[0,0],"direction":[1,0],"radius":4,"projectile_id":8,"velocity":[480,0]})
	s.projectiles = [{"id":8,"item_id":"wall_cannon","position":[8,0],"velocity":[480,0],"attack_id":"run:attack:1:0"}]
	d.consume(_events([launch]),s)
	t.check(_count(d.present(s),"projectile") == 1 and d.present(s)[0].origin == Vector2(8,0), "ordinary projectile uses the actual snapshot position")
	var impact := {"event_id":"run:2","type":"projectile_impact","tick":11,"payload":{"projectile_id":8,"attack_id":"run:attack:1:0","base_item_id":"wall_cannon","position":[12,0],"radius":40}}
	var damage := {"event_id":"run:3","type":"damage","tick":11,"payload":{"target_id":2,"position":[12,0],"item_id":"wall_cannon","amount":10}}
	var damage2 := damage.duplicate(true)
	damage2.event_id = "run:4"
	damage2.payload.target_id = 3
	d.consume(_events([impact,damage,damage2]),snapshot(11))
	t.check(_recipe_count(d.present(snapshot(11)),"wall_cannon.impact") == 1, "multi-target damage produces a single projectile explosion")
	t.check(_count(d.present(snapshot(11)),"projectile") == 0, "impact removes flight on contact frame")
	d.consume(_events([impact]),snapshot(11))
	t.check(_recipe_count(d.present(snapshot(11)),"wall_cannon.impact") == 1, "impact replay cannot duplicate explosion")
	d.reset("run")
	var cross := attack(1,"wall_cannon","evo_crossfire",10,46,"scheduled",{"shape":"circle","origin":[50,24],"direction":[1,0],"radius":56})
	d.consume(_events([cross]),snapshot(10))
	t.check(_count(d.present(snapshot(10)),"aim") == 1 and _count(d.present(snapshot(10)),"projectile") == 0, "crossfire begins with ground aim")
	t.check(_count(d.present(snapshot(28)),"projectile") == 1, "crossfire flight starts eighteen ticks before execute")
	var flying := _role(d.present(snapshot(45)),"projectile")
	t.check(not flying.is_empty() and flying.origin.distance_to(Vector2(50,24)) > 0.0, "crossfire flight is before contact, not after")
	cross.phase = "unused"
	var execute := attack(2,"wall_cannon","evo_crossfire",10,46,"executed",{"shape":"circle","origin":[50,24],"direction":[1,0],"radius":56})
	d.consume(_events([execute]),snapshot(46))
	t.check(_count(d.present(snapshot(46)),"projectile") == 0 and _count(d.present(snapshot(46)),"aim") == 0, "first execute frame terminates crossfire aim and flight")
	t.check(_role(d.present(snapshot(46)),"impact").origin == Vector2(50,24), "crossfire explosion touches its locked point")
	d.reset("run")
	d.consume(_events([execute]),snapshot(46))
	t.check(_count(d.present(snapshot(46)),"projectile") == 0 and _count(d.present(snapshot(46)),"impact") == 1, "executed-only delayed strike makes impact with no late flight")
	d.reset("run")
	var cross2 := attack(2,"wall_cannon","evo_crossfire",10,76,"scheduled",{"shape":"circle","origin":[50,-24],"direction":[1,0],"radius":56},1)
	d.consume(_events([attack(1,"wall_cannon","evo_crossfire",10,46,"scheduled",{"shape":"circle","origin":[50,24],"direction":[1,0],"radius":56}),cross2]),snapshot(10))
	t.check(_count(d.present(snapshot(10)),"aim") == 2, "crossfire preserves plus36 and plus66 independent locked points")
	t.check(_count(d.present(snapshot(58)),"projectile") == 1, "second flight respects its own lead window")
	d.reset("run",20)
	var restored := snapshot(30)
	restored.event_seq = 20
	restored.player_attack_instances = [{"attack_id":"run:attack:9:0","base_item_id":"wall_cannon","evolution_id":"evo_crossfire","attack_started_tick":10,"execute_tick":46,"stage_index":0,"origin":[50,24],"direction":[1,0],"shape":"circle","radius":56}]
	d.consume(_events([execute]),restored)
	t.check(_count(d.present(restored),"impact") == 0 and _count(d.present(restored),"aim") == 1, "restore only reconstructs future reservation and skips past event watermark")
	d.rebase(Vector2(100,200),1)
	var rebased := restored.duplicate(true)
	rebased.origin_revision = 1
	rebased.player_attack_instances[0].origin = [-50,-176]
	t.check(_role(d.present(rebased),"aim").origin == Vector2(-50,-176), "world origin rebase applies once")
	d.rebase(Vector2(100,200),1)
	t.check(_role(d.present(rebased),"aim").origin == Vector2(-50,-176), "same origin revision does not transform twice")
	d.reset("new_run")
	var new_snapshot := snapshot(10,"new_run")
	var new_event := event.duplicate(true)
	new_event.event_id = "new_run:1"
	new_event.payload.attack_id = "new_run:attack:1:0"
	d.consume(_events([new_event]),new_snapshot)
	t.check(_count(d.present(new_snapshot),"cast") == 1, "same seed fresh run can play fresh cast")
	d.reset("run")
	var wing := attack(1,"blade_slash","evo_wing_cut",10,22,"scheduled",{"shape":"sector","origin":[0,0],"direction":[1,0],"radius":88,"arc_degrees":110},1)
	d.consume(_events([wing]),snapshot(10))
	d.consume(_events([attack(2,"blade_slash","evo_wing_cut",10,22,"executed",{"shape":"sector","origin":[30,40],"direction":[1,0],"radius":88,"arc_degrees":110},1)]),snapshot(22))
	t.check(_role(d.present(snapshot(22)),"cast").origin == Vector2(30,40), "wing second stage uses current execute origin with locked direction")

	d.reset("run")
	var strong := snapshot(10)
	strong.equipment = {"blade_slash":5}
	d.consume(_events([event]),strong)
	t.check(d.present(strong)[0].intensity_tier == 3, "max equipment raises detail tier without changing contact radius")
	t.check(d.present(strong)[0].geometry.radius == 54, "equipment detail tier never changes core radius")
	d.reset("run")
	d.consume(_events([{"event_id":"run:1","type":"damage","tick":10,"payload":{"target_id":"player","source_id":"contact","amount":10,"hp":90}}]),snapshot(10))
	t.check(d.present(snapshot(10))[0].actor_id == "player", "core player damage binds to player actor")
	var restored_growth := snapshot(30,"restored_growth")
	restored_growth.erase("origin_revision")
	restored_growth.view_revision = 7
	restored_growth.player_attack_instances = [{"attack_id":"restored_growth:attack:9:0","base_item_id":"wall_cannon","evolution_id":"evo_crossfire","attack_started_tick":10,"execute_tick":46,"stage_index":0,"origin":[50,24],"direction":[1,0],"shape":"circle","radius":56}]
	t.check(d.present(restored_growth)[0].origin_revision == 0, "growth view revision is not a world origin revision")
	d.reset("run")
	for n in 64:
		var scheduled := attack(n+1,"wall_cannon","evo_crossfire",10,46,"scheduled",{"shape":"circle","origin":[n,24],"direction":[1,0],"radius":56})
		scheduled.payload.attack_id = "run:attack:"+str(n+1)+":0"
		d.consume(_events([scheduled]),snapshot(10))
	t.check(_count(d.present(snapshot(10)),"aim") == 64, "core reservation maximum preserves all active aim cues")
	t.check(_count(d.present(snapshot(28)),"projectile") == 64, "critical reserve preserves all lead-window shells")
	d.reset("run")
	var burst: Array[Dictionary] = []
	for n in 100000:
		burst.append({"event_id":"run:"+str(n+1),"tick":10,"type":"unrelated","payload":{}})
	d.consume(burst,snapshot(10))
	var stats: Dictionary = d.debug_stats()
	t.check(stats.event_seq == 100000 and stats.dedup_entries == 1, "one hundred thousand events keep constant dedup metadata")

	d.reset("run")
	for n in 40:
		var residual := attack(n+1,"blade_slash","",10,10,"executed",{"shape":"sector","origin":[0,0],"direction":[1,0],"radius":54})
		residual.payload.attack_id = "run:attack:"+str(n+1)+":0"
		d.consume(_events([residual]),snapshot(10))
	t.check(_count(d.present(snapshot(10)),"cast") == 40, "trail limit never removes first-frame actual blade contact")
	t.check(_count(d.present(snapshot(11)),"cast") == 32, "recovery residue respects adjustable trail pool")
	d.reset("run")
	for n in 12:
		d.consume(_events([{"event_id":"run:"+str(n+1),"type":"projectile_impact","tick":10,"payload":{"projectile_id":n,"attack_id":"run:attack:"+str(n+1)+":0","base_item_id":"wall_cannon","position":[n,0],"radius":40}}]),snapshot(10))
	t.check(_recipe_count(d.present(snapshot(10)),"wall_cannon.impact") == 12, "explosion budget never removes first-frame actual contacts")
	t.check(_recipe_count(d.present(snapshot(11)),"wall_cannon.impact") == 8, "after-contact large explosion recovery respects adjustable budget")
	_review_restore_revision(t,script)
	_review_independent_pool_defaults(t,script)
	_review_projectile_animation(t,script)
	_real_core_contracts(t,script)
	var small = script.new(null,{"effect_capacity":4,"trail_capacity":1,"explosion_capacity":1,"critical_reserve":0})
	t.check(not small.capacity_valid(64), "undersized pool reports inability to preserve core reservations")
	small.reset("run")
	for n in 20:
		var e := attack(n+1,"blade_slash","",10,10,"executed",{"shape":"sector","origin":[0,0],"direction":[1,0],"radius":54})
		e.payload.attack_id = "run:attack:"+str(n+1)+":0"
		small.consume(_events([e]),snapshot(10))
	t.check(small.debug_stats().effect_count <= 4, "effect pool remains bounded under burst")
func snapshot(tick: int, run_id := "run") -> Dictionary:
	return {"run_id":run_id,"seed":1,"event_seq":0,"active_tick":tick,"origin_revision":0,"player":{"id":"player","position":[0,0]},"projectiles":[],"entities":[],"player_attack_instances":[]}
func attack(seq: int, base: String, evo: String, start: int, execute: int, phase: String, geometry: Dictionary, stage := 0) -> Dictionary:
	return {"event_id":"run:"+str(seq),"type":"player_attack","tick":execute if phase == "executed" else start,"payload":{"cast_id":"run:attack:1","attack_id":"run:attack:1:"+str(stage),"base_item_id":base,"evolution_id":evo,"attack_started_tick":start,"execute_tick":execute,"phase":phase,"stage_index":stage,"origin":geometry.origin,"direction":geometry.direction,"geometry":geometry}}
func _count(effects: Array, role: String) -> int:
	return effects.filter(func(e): return e.role == role).size()
func _recipe_count(effects: Array, recipe: String) -> int:
	return effects.filter(func(e): return e.recipe_id == recipe).size()
func _role(effects: Array, role: String) -> Dictionary:
	for e in effects:
		if e.role == role: return e
	return {}

func _events(values: Array) -> Array[Dictionary]:
	var output: Array[Dictionary] = []
	for value in values: output.append(value)
	return output

func _real_core_contracts(t, script) -> void:
	var sim = Fixture.simulation(t)
	if sim == null: return
	for base in Fixture.EQUIPMENT_IDS:
		var state: Dictionary = sim.new_run(Fixture.chapter(),501,Fixture.run_config())
		state.equipment = {base:1}
		var d = script.new()
		d.reset(state.run_id)
		var emitted: Array[Dictionary] = Fixture.step(sim,state,Vector2.ZERO,[Fixture.spawn("vfx:"+base,[20.0,0.0])])
		var original := state.duplicate(true)
		d.consume(emitted,state)
		var visible: Array[Dictionary] = d.present(state)
		t.check(state == original, "actual core snapshot is immutable for "+base)
		t.check(Fixture.types(emitted,"player_attack").size() == 1, "actual core emits the documented attack for "+base)
		var has_main := false
		for effect in visible:
			if effect.get("base_item_id","") == base: has_main = true
		t.check(has_main, "actual six-base event stream produces skill-specific VFX for "+base)
	for evo in ["evo_wing_cut","evo_crossfire"]:
		var base := "blade_slash" if evo == "evo_wing_cut" else "wall_cannon"
		var state: Dictionary = sim.new_run(Fixture.chapter(),502,Fixture.run_config())
		state.equipment = {base:5}
		state.passives = {"movement":3} if evo == "evo_wing_cut" else {"fire_interval":3}
		state.evolutions = {base:evo}
		var d = script.new()
		d.reset(state.run_id)
		var contacts := 0
		for index in 70:
			var emitted: Array[Dictionary] = Fixture.step(sim,state,Vector2.RIGHT,[Fixture.spawn("vfx:"+evo,[20.0,0.0])] if index == 0 else [])
			d.consume(emitted,state)
			var visible: Array[Dictionary] = d.present(state)
			for event in Fixture.types(emitted,"player_attack"):
				if event.payload.phase != "executed": continue
				contacts += 1
				var found := false
				for effect in visible:
					if effect.attack_id == event.payload.attack_id and effect.role == ("cast" if evo == "evo_wing_cut" else "impact"):
						found = effect.origin == Vector2(event.payload.origin[0],event.payload.origin[1]) and effect.start_tick == event.payload.execute_tick
				t.check(found, "actual evolution contact uses exact execute origin/tick "+evo)
				if evo == "evo_crossfire":
					var flight_for_attack := visible.filter(func(effect): return effect.attack_id == event.payload.attack_id and effect.role == "projectile")
					t.check(flight_for_attack.is_empty(), "actual crossfire flight is absent on contact tick")
		t.check(contacts == 2, "actual evolution emits two separate executed stages "+evo)

func _review_restore_revision(t, script) -> void:
	var renderer = load("res://game/presentation/combat_vfx_renderer.gd").new()
	var catalog = load("res://game/presentation/combat_vfx_catalog.gd").new()
	var art = load("res://tests/presentation_vfx/test_catalog.gd").new().manifest_fixture(catalog)
	var s := snapshot(30)
	s.event_seq = 20
	s.origin_revision = 4 # Adapter value is stale; core nested world wins.
	s.world = {"origin_revision":7}
	s.player_attack_instances = [{"attack_id":"run:attack:9:0","base_item_id":"wall_cannon","evolution_id":"evo_crossfire","attack_started_tick":10,"execute_tick":46,"stage_index":0,"origin":[50,24],"direction":[1,0],"shape":"circle","radius":56}]
	s.projectiles = [{"id":8,"item_id":"wall_cannon","position":[8,0],"velocity":[480,0],"attack_id":"run:attack:1:0","radius":4}]
	var old := attack(19,"wall_cannon","evo_crossfire",10,20,"executed",{"shape":"circle","origin":[50,24],"direction":[1,0],"radius":56})
	var d = script.new()
	d.reset("run",20)
	d.consume(_events([old]),s)
	var effects: Array[Dictionary] = d.present(s)
	t.check(effects.size() == 3 and effects.all(func(e): return e.origin_revision == 7), "V1 explicit reset consume present initializes nested restored revision")
	t.check(_count(effects,"impact") == 0, "V1 restored revision initialization never replays old contact")
	var commands: Array[Dictionary] = renderer.commands(effects,{"tick":30,"origin_revision":7,"asset_metadata":art})
	t.check(commands.size() == 3 and commands.all(func(c): return not c.has("diagnostic")), "V1 restored aim and both flights pass current revision gate")
	t.check(d.present(s) == effects, "V1 repeated paused presentation preserves restored positions and revision")
	var fresh = script.new()
	var automatic: Array[Dictionary] = fresh.present(s)
	t.check(automatic.size() == 3 and automatic.all(func(e): return e.origin_revision == 7), "V1 automatic unseen-run restore consumes nested core revision")
	d.rebase(Vector2(100,200),8)
	var shifted := s.duplicate(true)
	shifted.world.origin_revision = 8
	shifted.player_attack_instances[0].origin = [-50,-176]
	shifted.projectiles[0].position = [-92,-200]
	var next: Array[Dictionary] = d.present(shifted)
	t.check(next.all(func(e): return e.origin_revision == 8) and _role(next,"aim").origin == Vector2(-50,-176), "V1 next genuine rebase transforms restored local coordinates once")
	d.rebase(Vector2(100,200),8)
	t.check(d.present(shifted) == next, "V1 repeated next revision never subtracts the offset twice")
	var flat := s.duplicate(true)
	flat.erase("world")
	flat.origin_revision = 7
	d.reset("run",20)
	t.check(d.present(flat).all(func(e): return e.origin_revision == 7), "V1 explicit reset also initializes legacy flat revision adapter")

func _review_independent_pool_defaults(t, script) -> void:
	for option in [{"trail_capacity":16},{"explosion_capacity":4},{"effect_capacity":80}]:
		var d = script.new(null,option)
		t.check(d.debug_stats().critical_reserve == 384 and d.capacity_valid(64), "V4 unrelated option retains default critical protection "+str(option))
	var constrained = script.new(null,{"critical_reserve":0})
	t.check(constrained.debug_stats().critical_reserve == 0 and not constrained.capacity_valid(64), "V4 only explicit reserve override removes default protection")
	var d = script.new(null,{"trail_capacity":16})
	d.reset("run")
	for n in 64:
		var scheduled := attack(n+1,"wall_cannon","evo_crossfire",10,46,"scheduled",{"shape":"circle","origin":[n,24],"direction":[1,0],"radius":56})
		scheduled.payload.attack_id = "run:attack:"+str(n+1)+":0"
		d.consume(_events([scheduled]),snapshot(10))
	t.check(_count(d.present(snapshot(10)),"aim") == 64 and _count(d.present(snapshot(28)),"projectile") == 64, "V4 one recovery override preserves all 64 core reservations and flights")

func _review_projectile_animation(t, script) -> void:
	var renderer = load("res://game/presentation/combat_vfx_renderer.gd").new()
	var catalog = load("res://game/presentation/combat_vfx_catalog.gd").new()
	var art = load("res://tests/presentation_vfx/test_catalog.gd").new().manifest_fixture(catalog)
	for base in ["wall_cannon","ally_cover"]:
		var d = script.new()
		d.reset("run")
		var s := snapshot(10)
		s.projectiles = [{"id":8,"item_id":base,"position":[8,0],"velocity":[480,0],"attack_id":"run:attack:1:0","radius":4}]
		d.consume(_events([attack(1,base,"",10,10,"executed",{"shape":"projectile","origin":[0,0],"direction":[1,0],"radius":4,"projectile_id":8,"velocity":[480,0]})]),s)
		var first := Rect2()
		var continuous := Rect2()
		for tick in [10,25,70,100,130,250]:
			s.active_tick = tick
			var context := {"tick":tick,"origin_revision":0,"asset_metadata":art}
			var effects: Array[Dictionary] = d.present(s)
			var commands: Array[Dictionary] = renderer.commands(effects,context)
			t.check(commands.size() == 1 and not commands[0].has("diagnostic"), "V2 live projectile persists independently of authored animation duration "+base+str(tick))
			if commands.is_empty() or commands[0].has("diagnostic"): continue
			var expected_frame := int(float(tick%120)/120.0*8.0)
			var expected_region := Rect2((expected_frame%4)*32,(expected_frame/4)*32,32,32)
			t.check(commands[0].atlas_region == expected_region, "V2 active-tick projectile frame advances and loops independently of sentinel "+base+str(tick))
			t.check(renderer.commands(d.present(s),context) == commands, "V2 paused active tick keeps identical flight frame "+base+str(tick))
			if tick == 10: first = commands[0].atlas_region
			if tick == 70:
				continuous = commands[0].atlas_region
				var restored = script.new()
				restored.reset("run",1)
				var recovered: Array[Dictionary] = restored.present(s)
				var restored_commands: Array[Dictionary] = renderer.commands(recovered,context)
				t.check(restored_commands.size() == 1 and restored_commands[0].atlas_region == continuous and _count(recovered,"impact") == 0, "V2 restored flight keeps continuous deterministic phase without replaying contact "+base)
			if tick == 130: t.check(commands[0].atlas_region == first, "V2 eight-frame sequence explicitly loops after 120 active ticks "+base)
		s.active_tick = 251
		s.projectiles = []
		d.consume(_events([{"event_id":"run:2","type":"projectile_impact","tick":251,"payload":{"projectile_id":8,"attack_id":"run:attack:1:0","base_item_id":base,"position":[12,0],"radius":40 if base == "wall_cannon" else 0}}]),s)
		t.check(_count(d.present(s),"projectile") == 0 and _count(d.present(s),"impact") == 1, "V2 actual contact still retires long-lived flight exactly once "+base)
