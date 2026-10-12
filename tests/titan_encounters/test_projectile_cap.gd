extends RefCounted
const Query = preload("res://game/combat/enemy_world_query.gd")
const Model = preload("res://game/combat/enemy_attack_model.gd")
const Roles = preload("res://game/combat/enemy_role_catalog.gd")
func run(t) -> void:
	var p: Dictionary = Roles.profile(Roles.read().catalog,"stone_thrower")
	var wall := {"bounds":[-500,-500,1000,1000],"obstacles":[[90,-60,20,120]]}
	var open := {"bounds":[-500,-500,1000,1000],"obstacles":[]}
	var begun: Dictionary = Model.begin_query({"id":1,"enemy_id":"stone_thrower","position":[0.0,0.0],"radius":24.0},{"position":[240.0,0.0]},1,p,Query.for_finite(wall),"test:enemy:1:1")
	t.check(begun.ok,"thrower cap fixture begins")
	if not begun.ok: return
	var cap := float(begun.get("grab_reach_cap",-1.0))
	t.check(cap >= 0.0 and cap < 90.0,"thrower persists first collision distance in existing role scalar")
	var after: Dictionary = Model.sample_query(begun.attack,int(begun.attack.active_from_tick)+30,Query.for_finite(open),cap)
	t.check(after.ok and not after.sample.projectile_pose.visible and after.sample.damage_geometry.is_empty(),"destroyed wall cannot resurrect an already stopped rock")

	p = Roles.profile(Roles.read().catalog,"quadruped")
	begun = Model.begin_query({"id":2,"enemy_id":"quadruped","position":[0.0,0.0],"radius":18.0},{"position":[150.0,0.0]},1,p,Query.for_finite(wall),"test:enemy:2:1")
	cap = float(begun.get("grab_reach_cap",-1.0))
	t.check(cap >= 0.0 and cap <= 72.0,"quadruped persists its warned body travel cap")
	after = Model.sample_query(begun.attack,int(begun.attack.active_from_tick)+30,Query.for_finite(open),cap)
	t.check(after.ok and float(after.sample.position[0]) <= 72.0,"removing a wall cannot teleport an already stopped quadruped")
