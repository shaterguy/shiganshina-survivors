extends RefCounted
const F = preload("res://tests/waiting_motion/fixture.gd")
const Audit = preload("res://tests/waiting_motion_simple/audit_core.gd")
func _audit(t, f: Dictionary, geometry: Dictionary) -> Dictionary:
	var sim = Audit.new(F.F.GeometryProvider.new(geometry,[0.0,0.0]))
	var result: Dictionary = sim.restore(f.state)
	t.check(result.get("ok",false),"instrumented terrain test preserves actual restore validation")
	if result.get("ok",false): f.sim=sim; f.state=result.state
	return f
func run(t) -> void:
	var f := F.make(t)
	var before := F.point(F.actor(f.state,"wait:0")); F.step(f)
	var dy := F.point(F.actor(f.state,"wait:0")).y-before.y
	var world := {"bounds":[-500.0,-500.0,1000.0,1000.0],"obstacles":[[124.0,-100.0,100.0,200.0],[60.0,24.0 if dy>0.0 else -124.0,64.0,100.0]]}
	f = F.make(t,[[100.0,0.0],[-150.0,0.0],[-130.0,-100.0]],world)
	f.state.entities = f.state.entities.filter(func(e): return str(e.id) in ["wait:0","pressure"])
	f = _audit(t,f,world)
	before = F.point(F.actor(f.state,"wait:0")); F.step(f)
	var audit: Dictionary = f.sim.audit
	t.check(audit.calls==1 and audit.world_moves==2,"blocked preferred uses exactly one real terrain alternate")
	t.check(F.point(F.actor(f.state,"wait:0")).distance_to(before)>.02,"mirrored finite alternate moves around the blocked preferred corner")
	t.check(audit.rows[0].moves[0].actual==[before.x,before.y],"first real terrain move is genuinely blocked")
	t.check(audit.hash_failures.is_empty(),"alternate actual endpoint relocates the existing shared hash exactly")
	F.write("terrain-alternate-simple.json",audit)
	world.obstacles.append([60.0,-124.0 if dy>0.0 else 24.0,64.0,100.0])
	f = F.make(t,[[100.0,0.0],[-150.0,0.0],[-130.0,-100.0]],world)
	f.state.entities = f.state.entities.filter(func(e): return str(e.id) in ["wait:0","pressure"])
	f = _audit(t,f,world)
	before = F.point(F.actor(f.state,"wait:0")); F.step(f)
	t.check(f.sim.audit.world_moves==2 and F.point(F.actor(f.state,"wait:0"))==before,"fully blocked geometry stops after at most two real world moves")
	F.write("terrain-blocked-simple.json",f.sim.audit)
	world = {"bounds":[-500.0,-500.0,1000.0,1000.0],"obstacles":[[124.0,-100.0,100.0,200.0]]}
	f = F.make(t,[[100.0,0.0],[-150.0,0.0],[-130.0,-100.0]],world)
	f.state.entities = f.state.entities.filter(func(e): return str(e.id) in ["wait:0","pressure"])
	f = _audit(t,f,world)
	before = F.point(F.actor(f.state,"wait:0"))
	F.F.step(f.sim,f.state,Vector2.ZERO,[F.F.spawn("peer",[80.0,0.0],"stone_thrower")])
	var row: Dictionary = f.sim.audit.rows[0]
	t.check(f.sim.audit.axis_clipped>0 and row.before!=row.after,"real axis-clipped endpoint still moves with permissive peers")
	t.check(F.Core.World.walkable(F.point(F.actor(f.state,"wait:0")),24.0,world),"actual clipped endpoint keeps terrain and attack-origin clearance")
	t.check(row.moves.size()==1,"moving clipped preferred does not trigger mirrored or peer-ranked alternatives")
	t.check(f.sim.audit.world_moves<=2 and f.sim.audit.hash_failures.is_empty(),"clipping preserves mover cap and exact spatial index")
	F.write("terrain-clipped-simple.json",f.sim.audit)
