extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
const N = preload("res://game/world/city_navigation.gd")
const Precise = preload("res://game/world/precise_city_navigation.gd")
const V = preload("res://game/world/streamed_navigation_view.gd")
const Exact = preload("res://game/world/streamed_world.gd")
const Cached = preload("res://game/world/cached_streamed_world.gd")
const Generator = preload("res://game/world/city_generator.gd")
const Oracle = preload("res://tests/smoothing_shortcut/oracle_navigation.gd")
const Tracing = preload("res://tests/direction_los_reuse/tracing_stream.gd")
const Opaque = preload("res://tests/review_smoothing_query_safety/opaque_view.gd")
const Derived = preload("res://tests/direction_los_reuse/derived_precise_navigation.gd")

func run(t) -> void:
	for cached in [false,true]:
		for precise in [false,true]: _one_query(t,cached,precise)
		_fraction_cases(t,cached)
		_masks_and_endpoint(t,cached)
		_failures(t,cached)
		_destruction_and_rebase(t,cached)
	_custom_callbacks(t)

func _world(cached: bool,chunks: Array = F.neighborhood(),mask: int = -1):
	var generator = F.generator()
	if mask >= 0:
		var props: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_props.json"))
		for definition in props.definitions.values():
			definition.collision_mask = mask
			definition.erase("mobility_anchor")
		generator = Generator.new(JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/city_templates.json")),props)
	var w = Cached.new(generator,42) if cached else Exact.new(generator,42)
	w.prepare(chunks,[],F.hydration(chunks),["0","0"])
	return w
func _begin(nav) -> void: nav._direction_los = nav._direction_reuse_scope()
func _q(w) -> int: return w.diagnostics().query_count
func _same(t,nav,oracle,a: Vector2,b: Vector2,radius: float,label: String) -> void:
	var actual: bool = nav._visible(a,b,radius)
	var expected: bool = oracle._visible(a,b,radius)
	t.check(actual == expected,label+": fraction==1 boolean exact")
	t.check(nav._world.navigation_query_status() == oracle._world.navigation_query_status(),label+": first observed failure exact")
	t.check(nav._world._world.diagnostics().last_error == oracle._world._world.diagnostics().last_error,label+": world last_error exact")

func _one_query(t,cached: bool,precise: bool) -> void:
	var w = _world(cached)
	var nav = Precise.new(V.new(w)) if precise else N.new(V.new(w))
	_begin(nav)
	var before := _q(w)
	t.check(nav._visible(Vector2(384,384),Vector2(640,384),8.0),"real fully resident street has clear LOS")
	t.check(_q(w)-before == 1,"RED: exact fully resident LOS uses one prop query without endpoint-position work")

func _fraction_cases(t,cached: bool) -> void:
	var a = _world(cached); var b = _world(cached)
	var prop: Dictionary = a.localized_chunk("0,0").props.filter(func(p): return (int(p.collision_mask) & 3) != 0)[0]
	var box: Rect2 = prop.ground_footprint
	var center := box.get_center()
	for radius in [0.0,8.0,8.0000000001,32.0]:
		var grown: Rect2 = box.grow(radius)
		var cases: Array = [
			[center,center],
			[center,Vector2(384,384)],
			[Vector2(384,384),Vector2(384,384)],
			[Vector2(grown.position.x-16,center.y),Vector2(grown.end.x+16,center.y)],
			[Vector2(grown.position.x-16,grown.position.y),Vector2(grown.end.x+16,grown.position.y)],
			[Vector2(grown.position.x-16,center.y),Vector2(grown.position.x,center.y)],
			[Vector2(384,384),Vector2(384.000030517578125,384)],
			[Vector2(767.99993896484375,384),Vector2(768.00006103515625,384)],
			[Vector2(-0.000030517578125,384),Vector2(0.000030517578125,384)]
		]
		for pair in cases:
			var nav = N.new(V.new(a)); var oracle = Oracle.new(V.new(b))
			_begin(nav)
			_same(t,nav,oracle,pair[0],pair[1],radius,"inside/zero/tangent/exact-end/tiny/reconstructed endpoint")

func _masks_and_endpoint(t,cached: bool) -> void:
	for mask in [1,2,3,0,4,8,16]:
		var a = _world(cached,F.neighborhood(),mask)
		var b = _world(cached,F.neighborhood(),mask)
		var prop: Dictionary = a.localized_chunk("0,0").props.filter(func(p): return p.ground_footprint.size.x > 0 and p.ground_footprint.size.y > 0)[0]
		var center: Vector2 = prop.ground_footprint.get_center()
		var nav = N.new(V.new(a)); var oracle = Oracle.new(V.new(b))
		_begin(nav)
		_same(t,nav,oracle,center,center,8.0,"non-player/titan collision mask")
		t.check(b.walkable(center,8.0) == (mask == 0),"mask fixture separates nonzero walkability from player/titan bits")
		t.check(nav._visible(center,center,8.0) == ((mask & 3) == 0),"mask1 and2 independently block; fraction==1 survives non-player/titan masks")

func _failures(t,cached: bool) -> void:
	for entry in [[Vector2(9000,384),8.0],[Vector2(1152,384),8.0],[Vector2(760.0001220703125,384),8.0],[Vector2(100000,384),8.0],[Vector2(INF,384),8.0],[Vector2(640,384),-1.0],[Vector2(640,384),33.0]]:
		var a = _world(cached,[["0","0"]]); var b = _world(cached,[["0","0"]])
		var nav = N.new(V.new(a)); var oracle = Oracle.new(V.new(b))
		_begin(nav)
		for pair in [[Vector2(640,384),8.0],entry,[Vector2(640,384),8.0]]:
			_same(t,nav,oracle,Vector2(384,384),pair[0],pair[1],"coverage/precision/radius failure followed by success")
		t.check(nav._direction_los.is_empty(),"actual failure retires earlier LOS observations")
		t.check(_q(a) == _q(b),"unsafe domain retains exact authoritative query count")
	# A pre-existing source error is never cleared or hidden by a bool fast path.
	var a = _world(cached); var b = _world(cached)
	for w in [a,b]: w.covered(Rect2(Vector2(20000,20000),Vector2.ONE))
	var nav = N.new(V.new(a)); var oracle = Oracle.new(V.new(b))
	_begin(nav)
	_same(t,nav,oracle,Vector2(384,384),Vector2(640,384),8.0,"pre-existing last_error")
	t.check(nav._direction_los.is_empty(),"pre-existing source failure disables shortcut")

func _destruction_and_rebase(t,cached: bool) -> void:
	var a = _world(cached); var b = _world(cached)
	var nav = N.new(V.new(a)); var oracle = Oracle.new(V.new(b))
	_begin(nav)
	_same(t,nav,oracle,Vector2(16,200),Vector2(280,200),8.0,"intact geometry")
	var changes: Array = []
	for prop in a.localized_chunk("0,0").props:
		if prop.destructible: changes.append({"slot_id":prop.slot_id,"hp":0,"destroyed":true})
	for w in [a,b]: t.check(w.apply_props([{"chunk":["0","0"],"props":changes}],1).ok,"public destruction applied")
	_same(t,nav,oracle,Vector2(16,200),Vector2(280,200),8.0,"destroyed props with prior LOS scope")
	_begin(nav)
	_same(t,nav,oracle,Vector2(16,200),Vector2(280,200),8.0,"destroyed props with fresh LOS scope")
	for w in [a,b]: t.check(w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["1","0"]).ok,"public origin/coverage replacement")
	_same(t,nav,oracle,Vector2(384,384),Vector2(640,384),8.0,"rebase with prior scope")
	_begin(nav)
	_same(t,nav,oracle,Vector2(384,384),Vector2(640,384),8.0,"rebase with fresh scope")

func _custom_callbacks(t) -> void:
	for kind in ["world","view","navigation"]:
		var a = Tracing.new(F.generator(),42) if kind == "world" else _world(false)
		var b = Tracing.new(F.generator(),42) if kind == "world" else _world(false)
		if kind == "world":
			for w in [a,b]: w.prepare(F.neighborhood(),[],F.hydration(F.neighborhood()),["0","0"])
		var va = Opaque.new(a) if kind == "view" else V.new(a)
		var vb = Opaque.new(b) if kind == "view" else V.new(b)
		var nav = Derived.new(va) if kind == "navigation" else N.new(va)
		var oracle = Oracle.new(vb)
		_begin(nav)
		for target in [Vector2(640,384),Vector2(480,384),Vector2(640,384)]:
			_same(t,nav,oracle,Vector2(384,384),target,8.0,"derived "+kind+" callback")
		t.check(_q(a) == _q(b),"derived callback authoritative count unchanged")
		if kind == "world": t.check(a.calls == b.calls,"derived world exact call order and arguments")
		if kind == "view": t.check(va.sweep_calls == vb.sweep_calls,"derived view exact call order and arguments")
