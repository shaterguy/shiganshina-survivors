extends RefCounted
const Fixture := preload("res://tests/enemy_roles/role_fixture.gd")
const Geometry := preload("res://game/combat/attack_geometry.gd")
const World := preload("res://game/combat/world_geometry.gd")
func run(t) -> void:
	var path := "res://game/combat/enemy_attack_model.gd"
	t.check(FileAccess.file_exists(path), "pure enemy attack model exists")
	if not FileAccess.file_exists(path): return
	var model = load(path)
	t.check(model != null and model.can_instantiate(), "enemy attack model compiles")
	if model == null or not model.can_instantiate(): return
	var catalog := Fixture.read_catalog(t)
	if catalog.is_empty(): return
	var api = load("res://game/combat/enemy_role_catalog.gd")
	test_half_open_boundaries(t,model,api,catalog)
	test_stationary_trigger_target_is_reachable(t,model,api,catalog)
	test_charge_stops_before_wall_and_has_no_ghost_lane(t,model,api,catalog)
	test_grab_and_sweep_hand_stop_at_solid(t,model,api,catalog)
	test_leap_legal_landing_and_airborne_no_damage(t,model,api,catalog)
	test_inputs_unchanged_and_json_roundtrip(t,model,api,catalog)
	test_radial_visibility_gate(t,model,api,catalog)
	test_malformed_sources_and_locks(t,model,api,catalog)
	test_visibility_discriminator_fails_closed(t,model)
func _begin(model,api,catalog: Dictionary,id: String,point: Array = [0.0,0.0],world: Dictionary = {}) -> Dictionary:
	return model.begin(Fixture.actor(id),Fixture.player(point),100,api.profile(catalog,id),world,"run:enemy:1:1")
func _hits(records: Array, point: Vector2, radius: float = 8.0) -> bool:
	for record in records:
		if Geometry.overlaps(record,point,radius): return true
	return false
func test_half_open_boundaries(t,model,api,catalog: Dictionary) -> void:
	var result := _begin(model,api,catalog,"runner",[96.0,0.0])
	t.check(result.ok,"runner begins at trigger edge")
	if not result.ok: return
	var attack: Dictionary = result.attack
	t.check(attack.active_from_tick == 145 and attack.attack_ends_tick == 187 and attack.recover_ends_tick == 253,"exact runner timeline")
	t.check(model.sample(attack,144,{}).damage_geometry.is_empty(),"no early damage")
	t.check(model.sample(attack,145,{}).phase == "attack","exact active boundary")
	t.check(model.sample(attack,187,{}).phase == "recover" and model.sample(attack,187,{}).damage_geometry.is_empty(),"safe recovery boundary")
	t.check(model.sample(attack,253,{}).finished,"exact completion boundary")
	t.check(model.sample(attack,99,{}).damage_geometry.is_empty(),"sampling before start is harmless")
	for id in Fixture.ROLE_IDS:
		var a: Dictionary = _begin(model,api,catalog,id).attack
		t.check(model.sample(a,int(a.active_from_tick)-1,{}).damage_geometry.is_empty(),id + " warning/airborne last tick harmless")
		t.check(not model.sample(a,int(a.active_from_tick),{}).damage_geometry.is_empty(),id + " exact active tick has geometry")
		for tick in [int(a.attack_ends_tick),int(a.attack_ends_tick)+15,int(a.recover_ends_tick)-1]:
			t.check(model.sample(a,tick,{}).damage_geometry.is_empty(),id + " recovery including hand return has no damage")
func test_stationary_trigger_target_is_reachable(t,model,api,catalog: Dictionary) -> void:
	for id in Fixture.ROLE_IDS:
		var p: Dictionary = api.profile(catalog,id)
		for offset in [-1.0,0.0]:
			var target := Vector2(float(p.trigger_range)+offset,0)
			var result := _begin(model,api,catalog,id,[target.x,target.y])
			t.check(result.ok,id + " begins within trigger")
			if not result.ok: continue
			var a: Dictionary = result.attack
			var reached := false
			for tick in range(int(a.active_from_tick),int(a.attack_ends_tick)):
				if _hits(model.sample(a,tick,{}).damage_geometry,target): reached = true
			t.check(reached,id + " actual body/hand reaches stationary trigger edge")
		t.check(not _begin(model,api,catalog,id,[float(p.trigger_range)+1.0,0]).ok,id + " outside trigger is deferred")
	var grab: Dictionary = _begin(model,api,catalog,"grabber",[190,0]).attack
	var g: Dictionary = model.sample(grab,175,{})
	t.check(g.position == [0.0,0.0] and g.velocity == [0.0,0.0],"grab body remains fixed")
	var sweep: Dictionary = _begin(model,api,catalog,"sweeper",[110,0]).attack
	var inner_reached := false
	for tick in range(160,178):
		if _hits(model.sample(sweep,tick,{}).damage_geometry,Vector2(50,0),0): inner_reached = true
	t.check(inner_reached,"sweeping arm damages inner radius, not merely hand-tip circumference")
func test_charge_stops_before_wall_and_has_no_ghost_lane(t,model,api,catalog: Dictionary) -> void:
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[70,-90,24,180]]}
	var a: Dictionary = _begin(model,api,catalog,"runner",[60,0],world).attack
	for tick in range(145,187):
		var sample: Dictionary = model.sample(a,tick,world)
		t.check(float(sample.position[0]) <= 54.0001,"charge body stops before expanded wall")
		t.check(not _hits(sample.damage_geometry,Vector2(102,0)),"charge has no wall-back damage")
	var open: Dictionary = _begin(model,api,catalog,"runner",[96,0]).attack
	var last: Dictionary = model.sample(open,186,{})
	t.check(last.position == [294.0,0.0],"runner traverses exactly 294 in 42 ticks")
	t.check(not _hits(last.damage_geometry,Vector2(40,0)),"already-passed charge lane is harmless")
	t.check(last.damage_geometry[0].length <= 7.001,"current body capsule is only one tick of motion")
	t.check(_hits(model.sample(open,144,{}).telegraph_geometry,Vector2(294,0)),"warning shows full future path")
func test_grab_and_sweep_hand_stop_at_solid(t,model,api,catalog: Dictionary) -> void:
	for wall_x in [30.0,90.0]:
		var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[wall_x,-250,20,500]]}
		for id in ["grabber","sweeper"]:
			var a: Dictionary = _begin(model,api,catalog,id,[20,0],world).attack
			for tick in range(int(a.active_from_tick),int(a.attack_ends_tick)):
				var sample: Dictionary = model.sample(a,tick,world)
				t.check(not _hits(sample.damage_geometry,Vector2(wall_x+29,0)),id + " shoulder/hand clipping prevents behind-wall damage")
				for geometry in sample.damage_geometry:
					if geometry.shape == "line":
						var start := Vector2(geometry.origin[0],geometry.origin[1])
						var end := start+Vector2(geometry.direction[0],geometry.direction[1])*float(geometry.length)
						t.check(World.walkable(start,float(geometry.width)*0.5,world) and World.walkable(end,float(geometry.width)*0.5,world),id + " neither capsule endpoint starts inside solid")
func test_leap_legal_landing_and_airborne_no_damage(t,model,api,catalog: Dictionary) -> void:
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[100,-100,20,200]]}
	var a: Dictionary = _begin(model,api,catalog,"leaper",[260,0],world).attack
	t.check(a.active_from_tick == 190,"leap has 66 warning plus 24 airborne ticks")
	for tick in range(166,190):
		var sample: Dictionary = model.sample(a,tick,world)
		t.check(sample.phase == "airborne" and sample.damage_geometry.is_empty(),"airborne body cannot damage player")
		t.check(float(sample.position[0]) <= 80.0001,"leap body cannot cross building")
	var landed: Dictionary = model.sample(a,190,world)
	t.check(World.walkable(Vector2(landed.position[0],landed.position[1]),20,world),"leap landing is legal")
	t.check(landed.damage_geometry[0].origin == landed.position,"landing circle matches actual landing")
	t.check(model.sample(a,100,world).telegraph_geometry[0].origin == landed.position,"landing warning matches clipped landing")
func test_inputs_unchanged_and_json_roundtrip(t,model,api,catalog: Dictionary) -> void:
	var actor := Fixture.actor("runner")
	var player := Fixture.player([96,0])
	var p: Dictionary = api.profile(catalog,"runner")
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[]}
	var before := [actor.duplicate(true),player.duplicate(true),p.duplicate(true),world.duplicate(true)]
	var a: Dictionary = model.begin(actor,player,100,p,world,"run:enemy:1:1").attack
	var a_before := a.duplicate(true)
	model.sample(a,170,world)
	t.check([actor,player,p,world] == before and a == a_before,"begin and sample never mutate input")
	t.check(model.validate(a,p).is_empty(),"attack validates")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(a,"",true,true))
	t.check(model.validate(restored,p).is_empty() and model.sample(restored,170,world) == model.sample(a,170,world),"attack JSON roundtrip replays exactly")
	p.rush_speed = 1
	t.check(a.profile.rush_speed == 420,"profile frozen by copy at begin")
	for field in ["source_id","phase_time","direction","hit_ids","unsafe","role","attack_id","profile"]:
		var bad := a.duplicate(true)
		match field:
			"source_id": bad.source_id = ""
			"phase_time": bad.attack_ends_tick += 0.5
			"direction": bad.locked_direction = [2,0]
			"hit_ids": bad.hit_target_ids = ["player","player"]
			"unsafe": bad.locked_origin = Vector2.ZERO
			"role": bad.role_id = "thrower_original"
			"attack_id": bad.attack_id = ""
			"profile": bad.profile.kind = "throw"
		t.check(not model.validate(bad,a.profile).is_empty(),"invalid attack rejected: " + field)
	var malformed := actor.duplicate(true)
	malformed.position = [NAN,0]
	t.check(not model.begin(malformed,player,100,a.profile,{},"run:enemy:1:1").ok,"begin refuses nonfinite position")
	t.check(not model.begin(actor,player,-1,a.profile,{},"run:enemy:1:1").ok,"begin refuses negative tick")

func test_radial_visibility_gate(t,model,api,catalog: Dictionary) -> void:
	t.check(model.has_method("visibility"),"model exposes shared radial/sector visibility predicate")
	if not model.has_method("visibility"): return
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[26,-100,10,200]]}
	for id in ["walker","brute","leaper"]:
		var a: Dictionary = _begin(model,api,catalog,id,[44,0],world).attack
		var sample: Dictionary = model.sample(a,int(a.active_from_tick),world)
		t.check(_hits(sample.damage_geometry,Vector2(44,0)),id + " raw radial/sector geometry deliberately overlaps wall-back target")
		var blocked: Dictionary = model.visibility(sample,Vector2(44,0),world)
		t.check(not blocked.visible and blocked.blocked_by_solid and blocked.required,id + " actual hit requires visibility and rejects wall-back target")
		t.check(model.visibility(sample,Vector2(-10,0),world).visible,id + " clear target remains visible")
		t.check(not model.visibility(sample,Vector2(44,10),world,Vector2(44,-10)).visible,id + " entire swept target path behind same solid is occluded")
		var cleared := {"bounds":world.bounds.duplicate(),"obstacles":[]}
		t.check(model.visibility(sample,Vector2(44,0),cleared).visible,id + " caller explicitly selects geometry snapshot after destruction")

func test_malformed_sources_and_locks(t,model,api,catalog: Dictionary) -> void:
	var profile: Dictionary = api.profile(catalog,"runner")
	for wrong in [NAN,INF,-1,0,1.5,true,null]:
		var actor := Fixture.actor("runner")
		actor.id = wrong
		t.check(not model.begin(actor,Fixture.player(),100,profile,{},"run:enemy:1:1").ok,"malformed numeric subject rejected")
	var different_body := Fixture.actor("runner")
	different_body.radius = 32
	t.check(not model.begin(different_body,Fixture.player(),100,profile,{},"run:enemy:1:1").ok,"actor body cannot disagree with approved collision radius")
	var a: Dictionary = _begin(model,api,catalog,"runner",[96,0]).attack
	var wrong_kind := a.duplicate(true)
	wrong_kind.kind = 3
	t.check(not model.validate(wrong_kind,profile).is_empty(),"wrong type in attack kind rejected without exception")
	var moved_target := a.duplicate(true)
	moved_target.locked_target = [9999.0,0.0]
	t.check(not model.validate(moved_target,profile).is_empty(),"serialized target cannot exceed trigger reach")
	var reversed := a.duplicate(true)
	reversed.locked_direction = [-1.0,0.0]
	t.check(not model.validate(reversed,profile).is_empty(),"serialized direction must agree with nonzero target vector")
	var narrow := {"bounds":[-500,-500,1000,1000],"obstacles":[[21,-100,20,200]]}
	t.check(not _begin(model,api,catalog,"grabber",[-30,0],narrow).ok,"hand capsule cannot originate inside a solid shoulder clearance")

func test_visibility_discriminator_fails_closed(t,model) -> void:
	var world := {"bounds":[-500,-500,1000,1000],"obstacles":[[26,-100,10,200]]}
	var malformed: Array[Dictionary] = [{}]
	for flag in [null,"bad",[],{},0,1]: malformed.append({"requires_visibility":flag,"visibility_origin":[0,0]})
	for sample_value in malformed:
		var result: Dictionary = model.visibility(sample_value,Vector2(60,0),world)
		t.check(result.get("error_code","") == "invalid_visibility_input","malformed/missing visibility flag returns structured error")
		t.check(result.get("required",false) and not result.get("visible",true) and result.get("blocked_by_solid",false),"unknown visibility semantics fail closed without exception")
	var clipped: Dictionary = model.visibility({"requires_visibility":false},Vector2(60,0),world)
	t.check(not clipped.required and clipped.visible and not clipped.blocked_by_solid and not clipped.has("error_code"),"explicit false remains valid for clipped capsule/legacy fixed-area semantics")
