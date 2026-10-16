extends RefCounted
const S = preload("res://tests/visibility_domain/support.gd")
func run(t) -> void:
	var before: int = t.cases.size()
	# Literal +/-zero Vector2 constants may share one GDScript constant-pool
	# entry. Decode distinct IEEE payloads at runtime, then check the actual
	# scalar and Vector2 bits before using those values as query fixtures.
	var negative_zero: float = _zero_with_sign(true)
	var positive_zero: float = _zero_with_sign(false)
	var negative_point := Vector2(negative_zero,negative_zero)
	var positive_point := Vector2(positive_zero,positive_zero)
	t.check(_float32_bits(negative_zero) == 0x80000000,"runtime negative-zero scalar has exact IEEE sign bit")
	t.check(_float32_bits(positive_zero) == 0x00000000,"runtime positive-zero scalar has exact IEEE bits")
	t.check(_float32_bits(negative_point.x) == 0x80000000 and _float32_bits(negative_point.y) == 0x80000000,"runtime negative-zero Vector2 retains both sign bits")
	t.check(_float32_bits(positive_point.x) == 0x00000000 and _float32_bits(positive_point.y) == 0x00000000,"runtime positive-zero Vector2 retains both zero sign bits")
	t.check(not S.same(negative_point,positive_point),"native fixture preserves signed-zero Vector2 payloads")
	for cached in [false,true]:
		_exact_domains(t,cached)
		_boundary_matrix(t,cached)
	t.check(t.cases.size()-before == 1716,"domain all 1716 comparisons returned")
	t.completed.append("test_domains.gd")
func _exact_domains(t, cached: bool) -> void:
	var single: Array = [["0","0"]]
	var positive_zero: float = _zero_with_sign(false)
	var negative_zero: float = _zero_with_sign(true)
	var p: Dictionary = S.pair(t,cached,[],single)
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(220,120),8.0,"single_no_neighbor_needed","one"),true,"single-cell admission")
	p = S.pair(t,cached,[],single)
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(768,120),0.0,"half_open_missing_endpoint_point","full"),true,"half-open endpoint remains successful fraction")
	S.expect_status(t,p,"world_not_ready","","","half-open endpoint backoff preserves world-only failure")
	p = S.pair(t,cached,[],[["0","0"],["1","0"]])
	S.expect_visible(t,S.query(t,p,Vector2(100,120),Vector2(768,120),0.0,"half_open_present_endpoint_point","one"),true,"new high cell included")
	p = S.pair(t,cached,[],[["-1","0"]])
	S.expect_visible(t,S.query(t,p,Vector2(-100,120),Vector2(0,120),0.0,"negative_half_open_missing_zero_point","full"),true,"negative half-open endpoint")
	S.expect_status(t,p,"world_not_ready","","","negative endpoint world-only failure")
	for entry in [
		["missing_source",Vector2(-1,120),Vector2(100,120),0.0],
		["missing_end",Vector2(100,120),Vector2(800,120),8.0],
		["span_over_eight",Vector2(100,120),Vector2(8000,120),0.0]
	]:
		p = S.pair(t,cached,[],single)
		var result: Dictionary = S.query(t,p,entry[1],entry[2],entry[3],entry[0],"full")
		t.check(not result.ok,"missing coverage returns actual failure")
		S.expect_status(t,p,"world_not_ready","world_not_ready","world_not_ready",entry[0])
	p = S.pair(t,cached,[],[["0","0"],["1","0"],["0","1"]])
	S.expect_visible(t,S.query(t,p,Vector2(384,384),Vector2(1152,384),8.0,"L_shape_no_extra_corner_needed","one"),true,"L-shaped residents admit horizontal sweep")
	for radius in [positive_zero,negative_zero,1.0e-46,0.00002,0.0001,0.00010001]:
		p = S.pair(t,cached,[],single)
		var signed_start := Vector2(negative_zero,negative_zero)
		var signed_target := Vector2(positive_zero,positive_zero)
		S.query(t,p,signed_start,signed_target,radius,"signed_zero_stationary_radius="+str(radius))
		t.cases[-1].signed_zero_input_bits = {"start":[_float32_bits(signed_start.x),_float32_bits(signed_start.y)],"target":[_float32_bits(signed_target.x),_float32_bits(signed_target.y)],"radius":_float32_bits(radius)}
	# These pinned traps distinguish the exact reconstruction from an ideal AABB.
	p = S.pair(t,cached,[],[["0","0"],["1","0"]])
	S.query(t,p,Vector2(768,120),Vector2(1536,120),0.00005,"rounded_endpoint_requires_cell_two","full")
	S.expect_status(t,p,"world_not_ready","","","positive-radius endpoint reconstruction error")
	p = S.pair(t,cached,[],[["-1","0"]])
	S.query(t,p,Vector2(0,120),Vector2(0.00000095367431640625,120),0.0,"empty_swept_span_missing_endpoint_point","full")
	S.expect_status(t,p,"world_not_ready","","","empty swept span does not erase upper endpoint requirement")
	p = S.pair(t,cached,[],single)
	S.query(t,p,Vector2(0,120),Vector2(0.00000095367431640625,120),0.0,"empty_swept_span_present_endpoint_point","one")
	p = S.pair(t,cached,[],[["-1","0"]])
	S.query(t,p,Vector2(0,120),Vector2(0,120),7.006492321624085e-46,"radius_two_to_minus150_operation_order","full")
	S.expect_status(t,p,"world_not_ready","world_not_ready","world_not_ready","radius rounds to point in native vector operation order")
func _boundary_matrix(t, cached: bool) -> void:
	# 840 stratified cases per native World form. This crosses every axis,
	# boundary, offset, radius and direction; mask/layout rotate deterministically
	# instead of multiplying runtime by another 7*3. Fresh fixtures avoid sticky
	# errors accidentally disabling the shortcut in later matrix entries.
	var index := 0
	var radii: Array = [_zero_with_sign(false),_zero_with_sign(true),1.0e-46,0.00002,8.01,32.0]
	t.check(_float32_bits(radii[0]) == 0x00000000 and _float32_bits(radii[1]) == 0x80000000,"boundary matrix retains distinct signed-zero radii")
	var masks: Array = [0,1,2,3,4,8,16]
	for axis in 2:
		for boundary in [-768.0,-128.0,0.0,128.0,768.0]:
			var ulp: float = 1.401298464324817e-45 if boundary == 0.0 else (0.00006103515625 if absf(boundary) == 768.0 else 0.0000152587890625)
			for offset in [-2.0*ulp,-ulp,-0.0001,0.0,0.0001,ulp,2.0*ulp]:
				for radius in radii:
					for reverse in [false,true]:
						var start := Vector2(256,256)
						var target := Vector2(320,320)
						start[axis] = boundary+32.0 if reverse else boundary-32.0
						target[axis] = boundary+offset
						var upper: Vector2 = start.max(start+(target-start))
						var chunks: Array = S.neighborhood(["0","0"],2)
						var layout: int = index%3
						if layout != 0:
							var point: Vector2 = upper if layout == 1 else start.min(start+(target-start))
							var cell: Array = [str(int(floor(point.x/768))),str(int(floor(point.y/768)))]
							chunks.erase(cell)
						var mask: int = masks[index%masks.size()]
						var records: Array = [S.prop("boundary",Rect2(target-Vector2(8,8),Vector2(16,16)),mask)]
						var p: Dictionary = S.pair(t,cached,records,chunks)
						S.query(t,p,start,target,radius,"stratum_%d_axis=%d_boundary=%.6f_layout=%d_mask=%d" % [index,axis,boundary,layout,mask])
						index += 1
	t.check(index == 840,"all stratified boundary cells visited")
func _zero_with_sign(negative: bool) -> float:
	# PackedByteArray construction and this method call are runtime operations.
	# Explicit little-endian IEEE bytes avoid equal floating constant pooling.
	var bytes := PackedByteArray([0,0,0,0])
	if negative: bytes[3] = 128
	return bytes.decode_float(0)
func _float32_bits(value: float) -> int:
	var bytes := PackedByteArray([0,0,0,0])
	bytes.encode_float(0,value)
	return bytes.decode_u32(0)
