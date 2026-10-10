extends SceneTree
const Sim = preload("res://game/core/run_simulation.gd")
const Catalog = preload("res://game/director/chapter_catalog.gd")
const World = preload("res://game/combat/world_geometry.gd")
const Attack = preload("res://game/combat/attack_geometry.gd")
var diagnosed := {}
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error("MAP_REVIEW FAIL: "+label)
func _initialize() -> void:
	call_deferred("run")
func legal(p: Vector2,r: float,w: Dictionary) -> bool:
	var b: Array = w.bounds
	if p.x < b[0]+r or p.x > b[0]+b[2]-r or p.y < b[1]+r or p.y > b[1]+b[3]-r: return false
	for a in w.obstacles:
		if p.x > a[0]-r and p.x < a[0]+a[2]+r and p.y > a[1]-r and p.y < a[1]+a[3]+r: return false
	return true
func vec(a: Array) -> Vector2:
	return Vector2(a[0],a[1])
func run() -> void:
	var chapter: Dictionary = Catalog.new().load_chapter("chapter_01_shiganshina").chapter
	var w: Dictionary = chapter.world_geometry
	var rng := RandomNumberGenerator.new()
	rng.seed = 73567
	var nav := World.new()
	for radius in [8.0,16.0,32.0]:
		for sample in 120:
			var start := Vector2(rng.randf_range(-640,640),rng.randf_range(-300,416))
			start = World.nearest_walkable(start,radius,w)
			check(legal(start,radius,w),"projected random start is independently walkable")
			for direction in [Vector2(rng.randf_range(-2000,2000),rng.randf_range(-2000,2000)),Vector2(10000,10000),Vector2(-10000,-10000)]:
				check(legal(World.move(start,direction,radius,w),radius,w),"swept walk cannot tunnel or escape")
				check(legal(World.sweep(start,direction,radius,w),radius,w),"blocked rush remains independently walkable")
			if sample < 24:
				var point := start
				for step in 1800:
					point = World.move(point,nav.direction(point,Vector2(0,360),radius,w)*1.5,radius,w)
					if point.distance_to(Vector2(0,360)) <= 1.5: break
				check(legal(point,radius,w) and point.distance_to(Vector2(0,360)) <= 1.5,"seeded actual-city route reaches dock")
	for obstacle in w.obstacles:
		var mid_y: float = obstacle[1]+obstacle[3]/2
		var start := Vector2(obstacle[0]-20,mid_y)
		var stopped := World.move(start,Vector2(1000,0),8,w)
		check(stopped.x == obstacle[0]-8 and legal(stopped,8,w),"each authored house blocks horizontal traversal")
		var slid := World.move(stopped,Vector2(3,3),8,w)
		check(slid.x == stopped.x and slid.y > stopped.y,"each house supports tangent sliding")
	var sim := Sim.new()
	for id in ["runner","grabber","boss_charger","boss_grabber","boss_abnormal","boss_leaper"]:
		var local := chapter.duplicate(true)
		local.initial_equipment = {}
		local.spawn_position = [632.0,408.0] if id == "boss_leaper" else [490.0,46.0]
		var state: Dictionary = sim.new_run(local,67)
		state.player.hp = 10000.0
		state.player.max_hp = 10000.0
		sim.step(state,Vector2.ZERO,[{"command_id":"actor","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":id,"position":[330.0,46.0]}}])
		var attack_samples := 0
		var blocked := false
		for tick in 400:
			var actor: Dictionary = state.entities[0]
			if actor.action_state != "airborne": check(legal(vec(actor.position),actor.radius,w),"real actor remains inside actual city: "+id)
			if actor.action_state == "attack":
				attack_samples += 1
				if actor.attack_kind in ["charge","grab"]:
					var hazard: Dictionary = state.telegraphs[0]
					for edge in 8:
						check(Attack.overlaps(hazard,vec(actor.position)+Vector2.from_angle(TAU*edge/8)*float(actor.radius),0.001),"actual-city blocked rush stays in capsule: "+id)
					if actor.position[0] <= 370-float(actor.radius)+0.001 and actor.position[0] >= 370-float(actor.radius)-0.01: blocked = true
			if tick%23 == 0:
				var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(state,"",true,true)))
				if not (restored.ok and restored.get("state",{}) == state) and not diagnosed.has(id):
					diagnosed[id] = true
					print("RESTORE_DIAG ",id," tick=",state.active_tick," action=",actor.action_state," result=",restored.get("error_code","ok")," diff=",leaf_diff(state,restored.get("state",{})))
				check(restored.ok and restored.get("state",{}) == state,"actual city action saves exactly: "+id)
				if restored.ok:
					sim.step(restored.state,Vector2.ZERO,[])
					sim.step(state,Vector2.ZERO,[])
					check(restored.state == state,"restored actual-city action replays exactly: "+id)
				else: sim.step(state,Vector2.ZERO,[])
			else: sim.step(state,Vector2.ZERO,[])
		check(attack_samples > 0,"actual-city fixture exercises action: "+id)
		if id != "boss_leaper": check(blocked,"actual-city fixture exercises physically blocked rush: "+id)
	for enemy_id in chapter.enemy_ids+["boss_charger","boss_sweeper","boss_leaper","boss_grabber","boss_abnormal"]:
		for edge in [[632.0,0.0],[-632.0,0.0],[0.0,-292.0],[0.0,408.0],[632.0,-292.0],[-632.0,-292.0],[632.0,408.0],[-632.0,408.0]]:
			var local := chapter.duplicate(true)
			local.initial_equipment = {}
			local.spawn_position = edge
			var state: Dictionary = sim.new_run(local,43)
			var outward := vec(edge).normalized()
			var requested := vec(edge)+outward*290.0
			sim.step(state,Vector2.ZERO,[{"command_id":"outward","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":enemy_id,"position":[requested.x,requested.y]}}])
			check(state.entities.size() == 1,"outbound wave remains spawnable: "+enemy_id)
			if state.entities.size() == 1:
				var actor: Dictionary = state.entities[0]
				check(legal(vec(actor.position),actor.radius,w) and vec(actor.position).distance_to(vec(edge)) > 100,"outbound relocation avoids immediate wall contact: "+enemy_id)
	var near_chapter := chapter.duplicate(true)
	near_chapter.initial_equipment = {}
	var near_state: Dictionary = sim.new_run(near_chapter,43)
	sim.step(near_state,Vector2.ZERO,[{"command_id":"valid_near","kind":"spawn_enemy","payload":{"entity_id":1,"enemy_id":"walker","position":[10.0,0.0]}}])
	check(vec(near_state.entities[0].position).distance_to(Vector2(10,0)) < 1.0,"valid intentional nearby spawn remains unchanged")
	print("MAP_REVIEW checks=%d failures=%d" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func leaf_diff(a: Variant,b: Variant,path := "root") -> String:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if not b.has(key): return path+"."+str(key)+" missing"
			if a[key] != b[key]: return leaf_diff(a[key],b[key],path+"."+str(key))
	elif a is Array and b is Array:
		for i in mini(a.size(),b.size()):
			if a[i] != b[i]: return leaf_diff(a[i],b[i],path+"["+str(i)+"]")
	return path+" "+str(a)+" != "+str(b)
