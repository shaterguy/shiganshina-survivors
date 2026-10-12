extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
static func preferred(state: Dictionary, entity: Dictionary, tick: int) -> Vector2:
	var band: Vector2 = {"stone_thrower":Vector2(180,250),"grabber":Vector2(115,155),"quadruped":Vector2(110,145)}[entity.enemy_id]
	var position := F.point(entity); var player := Vector2(state.player.position[0],state.player.position[1])
	var offset := position-player; var distance := offset.length()
	var away := offset.normalized() if distance>0.0001 else -Vector2(entity.facing[0],entity.facing[1])
	var next_distance := move_toward(distance,clampf(distance,band.x,band.y),float(entity.speed)*0.55/60.0)
	var phase := (tick-int(entity.role_wait_since)+str(entity.id).hash()%240)%240
	var angular_scale := float(entity.speed)*0.4*4.0/(TAU*(band.x+band.y)*0.5)
	var angle := angular_scale*(sin(TAU*float(phase)/240.0)-sin(TAU*float(phase-1)/240.0))
	return player+away.rotated(angle)*next_distance-position
func run(t) -> void:
	var f := F.make(t,[[130.0,0.0],[132.0,0.0],[134.0,0.0]])
	t.check(not f.sim.has_method("_waiting_ranked_motions") and not f.sim.has_method("_waiting_peer_score") and not f.sim.has_method("_waiting_outward_motion"),"simple preference removes peer ranking and outward machinery")
	var before: Dictionary = f.state.duplicate(true)
	F.step(f)
	t.check(f.sim.step_status().get("ok",false),"forced-peer step commits through the actual Core")
	for id in ["wait:0","wait:1","wait:2"]:
		var old := F.actor(before,id); var current := F.actor(f.state,id)
		var expected := F.point(old)+preferred(before,old,int(f.state.active_tick))
		t.check(F.point(current).distance_to(expected)<0.0001,"unblocked forced peers cannot redirect preferred waiting motion: "+id)
		t.check(current.role_wait_since==old.role_wait_since and current.action_state=="move","peer-independent motion retains age and denied action state: "+id)
