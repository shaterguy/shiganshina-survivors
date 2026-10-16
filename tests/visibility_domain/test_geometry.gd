extends RefCounted
const S = preload("res://tests/visibility_domain/support.gd")
func run(t) -> void:
	var before: int = t.cases.size()
	for cached in [false,true]:
		_geometry(t,cached)
		_real_geometry(t,cached)
	t.check(t.cases.size()-before == 114,"geometry all 114 comparisons returned")
	t.completed.append("test_geometry.gd")
func _geometry(t, cached: bool) -> void:
	var single: Array = [["0","0"]]
	var cases: Array = [
		["empty_single_cell",[],Vector2(100,120),Vector2(220,120),8.0,true],
		["outside_aabb_same_bucket",[S.prop("a",Rect2(128,200,20,20))],Vector2(100,120),Vector2(220,120),8.0,true],
		["tangent",[S.prop("a",Rect2(128,100,40,40))],Vector2(100,100),Vector2(220,100),0.0,true],
		["grown_tangent",[S.prop("a",Rect2(128,100,40,40))],Vector2(100,92),Vector2(220,92),8.0,true],
		["exact_touch",[S.prop("a",Rect2(128,100,40,40))],Vector2(100,120),Vector2(128,120),0.0,true],
		["grown_exact_touch",[S.prop("a",Rect2(128,100,40,40))],Vector2(100,120),Vector2(120,120),8.0,true],
		["inside_zero",[S.prop("a",Rect2(128,100,40,40))],Vector2(140,120),Vector2(140,120),0.0,false],
		["edge_zero",[S.prop("a",Rect2(128,100,40,40))],Vector2(128,120),Vector2(128,120),0.0,true],
		["outside_zero",[S.prop("a",Rect2(128,100,40,40))],Vector2(100,120),Vector2(100,120),0.0,true],
		["starts_inside",[S.prop("a",Rect2(128,100,40,40))],Vector2(140,120),Vector2(220,120),0.0,false],
		["reverse",[S.prop("a",Rect2(128,100,40,40))],Vector2(220,120),Vector2(100,120),8.01,false],
		["corner_only",[S.prop("a",Rect2(128,128,40,40))],Vector2(100,156),Vector2(156,100),0.0,true],
		["multibucket",[S.prop("a",Rect2(120,80,300,80))],Vector2(100,120),Vector2(500,120),8.0,false]
	]
	for entry in cases:
		var p: Dictionary = S.pair(t,cached,entry[1],single)
		for repeat in 2: S.expect_visible(t,S.query(t,p,entry[2],entry[3],entry[4],str(entry[0])+"_"+str(repeat),"one"),entry[5],entry[0])
	for mask in [0,1,2,3,4,8,16]:
		var p: Dictionary = S.pair(t,cached,[S.prop("mask",Rect2(128,100,40,40),mask,4)],single)
		S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"mask_"+str(mask),"one"),(mask & 3) == 0,"mask bits")
		S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(140,120),8.0,"mask_endpoint_inside_"+str(mask),"one"),(mask & 3) == 0,"mask endpoint visibility")
		if mask in [4,8,16]:
			var hit: Dictionary = p.worlds[1].sweep(Vector2(100,120),Vector2(40,0),8.0)
			t.check(hit.ok and hit.fraction == 1.0 and hit.position != Vector2(140,120),"non-mask3 still corrects endpoint without changing fraction")
	# Two additional independent geometries retain first/last blocker semantics.
	for first in [true,false]:
		var id: String = "a_block" if first else "z_block"
		var records: Array = [S.prop(id,Rect2(128,100,40,40)),S.prop("m",Rect2(140,100,10,40),0,4),S.prop("n",Rect2(180,100,10,40),4),S.prop("o",Rect2(180,200,10,10)),S.prop("p",Rect2(220,220,10,10))]
		var p: Dictionary = S.pair(t,cached,records,single)
		S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"sorted_blocker_"+str(first),"one"),false,"sorted blocker")
func _real_geometry(t, cached: bool) -> void:
	var p: Dictionary = S.pair(t,cached,[],S.neighborhood(["0","0"],2),["0","0"],true)
	for radius in [0.0,0.00002,8.01,18.0,32.0]:
		for endpoints in [[Vector2(432,194),Vector2(640,384)],[Vector2(100,100),Vector2(384,384)],[Vector2(672,762),Vector2(1152,384)]]:
			S.query(t,p,endpoints[0],endpoints[1],radius,"real_r="+str(radius)+"_start="+str(endpoints[0]))
