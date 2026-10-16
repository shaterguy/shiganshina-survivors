extends RefCounted
const S = preload("res://tests/visibility_domain/support.gd")
const FullNavigation = preload("res://tests/visibility_domain/full_navigation.gd")
func run(t) -> void:
	var before: int = t.cases.size()
	for cached in [false,true]:
		for entry in [
			["clear",[],Vector2(100,120),Vector2(220,120),8.0,""],
			["endpoint_mask4",[S.prop("a",Rect2(128,100,40,40),4)],Vector2(100,120),Vector2(140,120),8.0,"blocked"],
			["source_blocked",[S.prop("a",Rect2(128,100,40,40))],Vector2(140,120),Vector2(220,120),8.0,"blocked"],
			["missing_endpoint_point",[],Vector2(100,120),Vector2(768,120),0.0,"world_not_ready"],
			["missing_swept_end",[],Vector2(100,120),Vector2(800,120),8.0,"world_not_ready"],
			["invalid_length",[],Vector2.ZERO,Vector2(40000,40000),0.0,"invalid_query"],
			["unsupported_radius",[],Vector2(100,120),Vector2(220,120),33.0,"unsupported_radius"]
		]:
			var p: Dictionary = S.pair(t,cached,entry[1],[["0","0"]])
			p.helpers[0]._navigation = S.Helper.Navigation.new(p.views[0])
			p.helpers[1]._navigation = FullNavigation.new(p.views[1])
			var label: String = "helper_direction_"+str(entry[0])
			var actual: Dictionary = p.helpers[0].direction(entry[2],entry[3],entry[4],10)
			var full: Dictionary = p.helpers[1].direction(entry[2],entry[3],entry[4],10)
			t.check(S.same(actual,full),label+": complete actual helper direction equals full-sweep oracle")
			t.check(S.same(p.helpers[0].query_status(),p.helpers[1].query_status()),label+": complete helper query_status")
			t.check(S.same(p.helpers[0]._query_failure,p.helpers[1]._query_failure),label+": helper raw first failure")
			t.check(S.same(p.views[0]._query_failure,p.views[1]._query_failure),label+": View raw first failure")
			t.check(S.same(S.diagnostics_without_work_count(p.worlds[0]),S.diagnostics_without_work_count(p.worlds[1])),label+": all nonwork world diagnostics")
			t.check(p.helpers[0].query_status().get("error_code","") == entry[5],label+": independent helper status")
			t.cases.append({"name":label,"cached":cached,"actual":actual,"full":full,"helper_status":p.helpers[0].query_status(),"last_error":p.worlds[0]._last_error,"query_counts_candidate_full":[p.worlds[0]._query_count,p.worlds[1]._query_count],"count_policy":"helper_integration_work_may_differ"})
	t.check(t.cases.size()-before == 14,"all 14 helper integration comparisons returned")
	t.completed.append("test_helper.gd")
