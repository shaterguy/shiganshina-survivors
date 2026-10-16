extends RefCounted
const S = preload("res://tests/visibility_domain/support.gd")
# Candidate-only API contract checks. This body is selected only by --mode=proof.
# It must not be used to claim that the unchanged baseline has this new API.
func run(t) -> void:
	var before: int = t.cases.size()
	for cached in [false,true]:
		for entry in [
			["single_interior",[["0","0"]],Vector2(100,120),Vector2(120,0),8.0,true],
			["point_endpoint_missing",[["0","0"]],Vector2(100,120),Vector2(668,0),0.0,false],
			["point_endpoint_present",[["0","0"],["1","0"]],Vector2(100,120),Vector2(668,0),0.0,true],
			["rounded_high_missing",[["0","0"],["1","0"]],Vector2(768,120),Vector2(768,0),0.00005,false],
			["rounded_high_present",[["0","0"],["1","0"],["2","0"]],Vector2(768,120),Vector2(768,0),0.00005,true],
			["empty_sweep_high_missing",[["0","0"]],Vector2(768,120),Vector2(0.00000095367431640625,0),0.0,false],
			["empty_sweep_high_present",[["1","0"]],Vector2(768,120),Vector2(0.00000095367431640625,0),0.0,true],
			["subnormal_radius_point_missing",[["-1","0"]],Vector2(0,120),Vector2.ZERO,7.006492321624085e-46,false],
			["original_span_gt_eight",[["0","0"]],Vector2(100,120),Vector2(8000,0),0.0,false]
		]:
			var p: Dictionary = S.pair(t,cached,[],entry[1])
			var bounds: Rect2 = S.Stream._swept_rect(entry[2],entry[3],entry[4])
			var world_before: Dictionary = p.worlds[0].diagnostics().duplicate(true)
			var query_before: Dictionary = p.views[0]._query_failure.duplicate(true)
			var helper_before: Dictionary = p.helpers[0].query_status()
			var cache_before: Dictionary = p.worlds[0].coverage_cache_stats() if cached else {}
			var ready: bool = p.views[0]._visibility_domain_ready(bounds,entry[2],entry[3],entry[4])
			t.check(ready == entry[5],str(entry[0])+": independent candidate proof expectation")
			t.check(S.same(world_before,p.worlds[0].diagnostics()),str(entry[0])+": proof reads never modify world diagnostics")
			t.check(S.same(query_before,p.views[0]._query_failure) and S.same(helper_before,p.helpers[0].query_status()),str(entry[0])+": proof reads never observe a query failure")
			if cached: t.check(S.same(cache_before,p.worlds[0].coverage_cache_stats()),str(entry[0])+": proof never warms coverage cache")
			t.cases.append({"name":"proof_"+str(entry[0]),"cached":cached,"ready":ready,"expected":entry[5],"count_policy":"pure_zero_queries"})
			if entry[0] == "rounded_high_missing":
				var upper: Vector2 = entry[2].max(entry[2]+entry[3])
				var endpoint := Rect2(upper-Vector2.ONE*entry[4],Vector2.ONE*entry[4]*2)
				t.check(bounds.end.x == 1536.0 and endpoint.end.x == 1536.0001220703125,"pin native separately rounded rectangle endpoints")
			if entry[0] == "subnormal_radius_point_missing":
				var native_width: Vector2 = Vector2.ONE*entry[4]*2
				var regrouped_width: Vector2 = Vector2.ONE*(entry[4]*2)
				t.check(native_width.x == 0.0 and regrouped_width.x > 0.0,"pin scalar conversion and vector multiplication order")
	t.check(t.cases.size()-before == 18,"all 18 candidate proof comparisons returned")
	t.completed.append("test_proof.gd")
