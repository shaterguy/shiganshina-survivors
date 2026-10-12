extends RefCounted
# Real StreamedWorld implementation; synthetic geometry only exists in this fixture.
const W = preload("res://game/world/streamed_world.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
class FixtureGenerator extends RefCounted:
	var props: Array = []
	func _init(values: Array) -> void: props = values
	func generate(_seed: int, chunk: Array) -> Dictionary:
		return {"chunk":chunk.duplicate(),"chunk_id":chunk[0]+","+chunk[1],"geometry_revision":0,"props":props.duplicate(true) if chunk == ["0","0"] else [],"passage_rect":Rect2(360,360,48,48),"street_nodes":[]}
	func hydrate(chunk: Dictionary, _deltas: Array) -> Dictionary:
		return {"ok":true,"chunk":chunk.duplicate(true)}
func prop(id: String, rect: Rect2) -> Dictionary:
	return {"prop_id":id,"slot_id":id,"position":rect.position,"ground_footprint":rect,"render_bounds":rect,"depth_y":rect.end.y,"collision_mask":3,"cover_mask":3,"destructible":false,"hp":1,"max_hp":1,"destroyed":false}
func world(values: Array = []):
	var w = W.new(FixtureGenerator.new(values),42)
	w.prepare([["0","0"]],[],{"0,0":[]},["0","0"])
	return w
func cases() -> Array:
	var obstacle := [prop("b",Rect2(200,200,100,100))]
	var ties := [prop("z",Rect2(200,100,60,200)),prop("a",Rect2(200,100,60,200)),prop("corner",Rect2(100,200,200,60))]
	var result: Array = []
	for d in [Vector2.ZERO,Vector2(-0.0,0.0),Vector2(25,0),Vector2(-25,0),Vector2(0,25),Vector2(0,-25),Vector2(25,25),Vector2(-25,25),Vector2(25,-25),Vector2(-25,-25),Vector2(1e-8,0),Vector2(0,-1e-8),Vector2(1e-8,-1e-8)]:
		result.append({"name":"empty_%d"%result.size(),"p":Vector2(384,384),"d":d,"r":8.0,"props":[]})
	for d in [Vector2.ZERO,Vector2(20,0),Vector2(0,20),Vector2(20,20),Vector2(-80,-80),Vector2(1e-8,0)]:
		result.append({"name":"overlap_%d"%result.size(),"p":Vector2(250,250),"d":d,"r":8.0,"props":obstacle})
	for p in [Vector2(100,250),Vector2(192,250),Vector2(250,100),Vector2(192,192)]:
		for d in [Vector2(200,0),Vector2(0,200),Vector2(200,200),Vector2(0,1e-8),Vector2.ZERO]:
			result.append({"name":"contact_%d"%result.size(),"p":p,"d":d,"r":8.0,"props":obstacle})
	for d in [Vector2(200,0),Vector2(0,200),Vector2(200,200),Vector2(100,100),Vector2.ZERO]:
		result.append({"name":"tie_%d"%result.size(),"p":Vector2(100,150),"d":d,"r":8.0,"props":ties})
	for r in [0.0,8.0,16.0,18.0,20.0,24.0,28.0,30.0,32.0,7.999999,8.000001]:
		result.append({"name":"radius_%d"%result.size(),"p":Vector2(100,250),"d":Vector2(200,0),"r":r,"props":obstacle})
	for pair in [[Vector2(800,384),Vector2.ZERO],[Vector2(768,384),Vector2.ZERO],[Vector2(767,384),Vector2(2,0)],[Vector2(384,384),Vector2(10000,0)],[Vector2(-1,384),Vector2.ZERO],[Vector2(0,384),Vector2.ZERO]]:
		result.append({"name":"coverage_%d"%result.size(),"p":pair[0],"d":pair[1],"r":8.0,"props":[]})
	for r in [-1.0,32.000001,INF,-INF,NAN]:
		result.append({"name":"invalid_radius_%d"%result.size(),"p":Vector2(384,384),"d":Vector2.ZERO,"r":r,"props":[]})
	for p in [Vector2(INF,384),Vector2(384,-INF),Vector2(NAN,384),Vector2(384,NAN),Vector2(49153,384)]:
		result.append({"name":"invalid_position_%d"%result.size(),"p":p,"d":Vector2.ZERO,"r":8.0,"props":[]})
	for d in [Vector2(INF,0),Vector2(0,NAN),Vector2(0,-INF),Vector2(49153,0)]:
		result.append({"name":"invalid_delta_%d"%result.size(),"p":Vector2(384,384),"d":d,"r":8.0,"props":[]})
	for d in [Vector2(1e-8,0),Vector2(0,-1e-8),Vector2(1e-8,-1e-8)]:
		result.append({"name":"representable_tiny_%d"%result.size(),"p":Vector2(1e-6,1e-6),"d":d,"r":0.0,"props":[]})
	return result
func run(t) -> void:
	# Removing the exact-zero skip breaks these query-count assertions. Replacing
	# it with is_zero_approx breaks the tiny-nonzero checks below.
	for d in [Vector2.ZERO,Vector2(-0.0,0.0),Vector2(25,0),Vector2(-25,0),Vector2(0,25),Vector2(0,-25),Vector2(25,25),Vector2(1e-8,0),Vector2(0,1e-8),Vector2(1e-8,1e-8)]:
		var w = world()
		var p := Vector2(384,384)
		var result: Vector2 = w.move(p,d,8)
		var expected: int = (int(d.x != 0.0)+int(d.y != 0.0))*2
		t.check(result == p+d,"axis displacement exact: "+str(d))
		t.check(w.diagnostics().query_count == expected,"exact-zero query budget delta=%s expected=%d actual=%d"%[str(d),expected,w.diagnostics().query_count])
	for d in [Vector2(1e-8,0),Vector2(0,-1e-8),Vector2(1e-8,-1e-8)]:
		var tiny = world()
		var p := Vector2(1e-6,1e-6)
		var moved: Vector2 = tiny.move(p,d,0)
		t.check(moved == p+d and moved != p,"representable tiny-nonzero movement is never skipped")
		t.check(tiny.diagnostics().query_count == (int(d.x != 0.0)+int(d.y != 0.0))*2,"representable tiny-nonzero axis still sweeps")
	var empty = world()
	var unchanged: Vector2 = empty.move(Vector2(800,384),Vector2.ZERO,8)
	t.check(unchanged == Vector2(800,384) and empty.diagnostics().last_error == "world_not_ready","zero move still preflights coverage")
	var invalid = world()
	invalid.move(Vector2(384,384),Vector2.ZERO,NAN)
	t.check(invalid.diagnostics().query_count == 0 and invalid.diagnostics().last_error == "","invalid radius remains rejected before any sweep")
	var tied = world([prop("z",Rect2(200,100,60,200)),prop("a",Rect2(200,100,60,200))])
	var hit: Dictionary = tied.sweep(Vector2(100,150),Vector2(200,0),8)
	t.check(hit.hit_prop_id == "a" and hit.position == Vector2(192,150),"first-collision tie still chooses lexicographically first prop")
	var corner = world([prop("vertical",Rect2(200,100,60,200)),prop("horizontal",Rect2(100,200,200,60))])
	t.check(corner.move(Vector2(100,150),Vector2(200,200),8) == Vector2(192,192),"multiple-collider corner keeps exact X-then-Y contact")
	adapter_checks(t)
func adapter_checks(t) -> void:
	var h = H.new(HF.definitions())
	var state: Dictionary = HF.state(h)
	t.check(h.prepare(state,HF.hydration(H.requirements(state))).ok,"actual StreamedRunWorld prepares actual seed42 city")
	for spec in [{"p":Vector2(8000,384),"r":8.0,"code":"world_not_ready"},{"p":Vector2(384,384),"r":NAN,"code":"unsupported_radius"},{"p":Vector2(384,384),"r":-1.0,"code":"unsupported_radius"},{"p":Vector2(INF,384),"r":8.0,"code":"invalid_query"},{"p":Vector2(NAN,384),"r":8.0,"code":"invalid_query"}]:
		t.check(h.begin_query_batch(state).ok,"adapter begins zero-move error batch")
		var result: Dictionary = h.move(spec.p,Vector2.ZERO,spec.r)
		t.check(not result.ok and result.error_code == spec.code,"adapter zero-move propagates "+spec.code)
		t.check(h.query_status() == result,"adapter zero-move failure becomes sticky")
		var after: Dictionary = h.move(Vector2(384,384),Vector2.ZERO,8)
		t.check(after.ok and after.position == Vector2(384,384) and h.query_status() == result,"later valid zero move cannot erase sticky error")
	var cold = H.new(HF.definitions())
	var cold_result: Dictionary = cold.move(Vector2(384,384),Vector2.ZERO,8)
	t.check(not cold_result.ok and cold_result.error_code == "world_not_ready" and cold.query_status() == cold_result,"unprepared actual adapter zero-move fails closed")
func scalar(v: float) -> Variant:
	if is_nan(v): return "NAN"
	if is_inf(v): return "INF" if v > 0 else "-INF"
	return v
func vec(v: Vector2) -> Array: return [scalar(v.x),scalar(v.y)]
func capture() -> Dictionary:
	var rows: Array = []
	for c in cases():
		var w = world(c.props)
		var before: Dictionary = w.diagnostics()
		var point: Vector2 = w.move(c.p,c.d,c.r)
		rows.append({"name":c.name,"position":vec(point),"delta":vec(c.d),"radius":scalar(c.r),"before":before,"after":w.diagnostics()})
	# Seed42 generated city, fresh per move so cache effects are visible.
	for p in [Vector2(384,384),Vector2(16,200),Vector2(0,300),Vector2(144,224),Vector2(384,720)]:
		for d in [Vector2.ZERO,Vector2(240,0),Vector2(0,160),Vector2(240,160),Vector2(-80,-80),Vector2(1e-8,0),Vector2(0,1e-8)]:
			for r in [8.0,32.0]:
				var w = F.world(F.neighborhood())
				var before: Dictionary = w.diagnostics()
				rows.append({"name":"city_%d"%rows.size(),"position":vec(w.move(p,d,r)),"delta":vec(d),"radius":r,"before":before,"after":w.diagnostics()})
	# Warm sequential path captures propagation of prior sticky coverage errors.
	var warm = F.world(F.neighborhood())
	var point := Vector2(384,384)
	for d in [Vector2.ZERO,Vector2(10,0),Vector2(0,10),Vector2(10,10),Vector2(0,10000),Vector2.ZERO,Vector2(-10,0),Vector2(1e-8,0)]:
		var before: Dictionary = warm.diagnostics()
		point = warm.move(point,d,8)
		rows.append({"name":"warm_%d"%rows.size(),"position":vec(point),"delta":vec(d),"radius":8.0,"before":before,"after":warm.diagnostics()})
	return {"rows":rows}
