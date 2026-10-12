extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
const Axis = preload("res://tests/movement_axis_equivalence/axis_cases.gd")
const Navigation = preload("res://game/world/precise_city_navigation.gd")
const View = preload("res://game/world/streamed_navigation_view.gd")
func run(t) -> void:
	var f := F.make(t)
	if f.is_empty(): return
	# Synthetic one-box geometry with the unmodified real StreamedWorld sweep,
	# axis move and precise navigation implementations. Tangent diagonal is clear,
	# while the intermediate X-only leg intersects the radius-expanded box corner.
	var axis = Axis.new()
	var world = axis.world([axis.prop("corner",Rect2(200,200,100,100))])
	f.sim._streamed._world = world
	f.sim._streamed._navigation = Navigation.new(View.new(world))
	var actor: Dictionary = f.state.entities[0].duplicate(true)
	actor.position = [181.8,182.05]
	actor.velocity = f.sim._array(Vector2(1,-1).normalized()*float(actor.speed))
	actor.action_started_tick = int(f.state.active_tick)-10
	while (int(f.state.active_tick)+str(actor.id).hash())%3 == 0: f.state.active_tick += 1
	f.state.player.position = [328.0,250.0]
	var start: Vector2 = f.sim._vec(actor.position)
	var delta: Vector2 = f.sim._vec(actor.velocity)/60.0
	var sweep: Dictionary = f.sim._streamed.sweep(start,delta,18.0)
	var moved: Dictionary = f.sim._streamed.move(start,delta,18.0)
	t.check(sweep.get("ok",false) and sweep.fraction==1.0 and moved.position.distance_to(start+delta)>0.00001,"shortened fixture uses real clear diagonal and real shortened axis move")
	F.clear(f.sim)
	var direction: Vector2 = f.sim._direction_world(f.state,start,f.sim._vec(f.state.player.position),18.0,str(actor.id))
	var expected: Vector2 = f.sim._move_world(f.state,start,direction*float(actor.speed)/60.0,18.0)
	F.clear(f.sim)
	f.sim._move_pursuing_enemy(f.state,actor)
	t.check(f.sim._streamed.trace.routes.size()==1 and f.sim._streamed.trace.moves.size()==2,"shortened actual movement triggers same-tick authoritative replanning")
	t.check(f.sim._streamed.trace.moves.size()==2 and f.sim._streamed.trace.moves[0].position==start and f.sim._streamed.trace.moves[1].position==start,"both movement queries start at the same original position")
	t.check(f.sim._vec(actor.position)==expected,"only final authoritative movement is committed")
