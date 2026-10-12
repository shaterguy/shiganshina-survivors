extends RefCounted
const F = preload("res://tests/world/fixtures/city_fixture.gd")
func run(t) -> void:
	var path := "res://game/world/streamed_world.gd"
	t.check(FileAccess.file_exists(path),"StreamedWorld module exists")
	if not FileAccess.file_exists(path): return
	var w = F.world()
	t.check(w.diagnostics().resident_chunks == 1,"lazy load does not build full 49-chunk envelope")
	var before: Dictionary = w.render_view()
	var missing: Dictionary = w.prepare([["0","0"],["1","1"]],[],{"0,0":[]},["0","0"])
	t.check(not missing.ok and missing.missing_delta_keys == ["1,1"] and w.render_view() == before,"missing hydration is typed and atomic")
	var chunks := F.neighborhood()
	t.check(w.prepare(chunks,[],F.hydration(chunks),["0","0"]).ok,"forward strip becomes ready")
	for radius in [8.0,16.0,18.0,20.0,24.0,28.0,30.0,32.0]:
		var start := Vector2(16,200)
		var hit: Dictionary = w.sweep(start,Vector2(200,0),radius)
		t.check(hit.ok and hit.fraction < 1 and not hit.hit_prop_id.is_empty() and w.walkable(hit.position,radius),"exact radius swept contact stays walkable")
		var slide: Vector2 = w.move(start,Vector2(240,160),radius)
		t.check(w.walkable(slide,radius),"diagonal slide stays outside house")
	var unloaded: Dictionary = w.sweep(Vector2(384,384),Vector2(10000,10000),8)
	t.check(not unloaded.ok and unloaded.position == Vector2(384,384) and unloaded.error_code == "world_not_ready","unloaded sweep never tunnels or fabricates a wall")
	var prop: Dictionary = w.chunk_at(Vector2(144,224)).props.filter(func(p): return p.slot_id == "nw_house")[0]
	var patch := [{"chunk":["0","0"],"props":[{"slot_id":prop.slot_id,"hp":2,"destroyed":false}]}]
	t.check(w.apply_props(patch,1).ok,"explicit prop changes accepted")
	var swapped: Dictionary = w.prepare([["1","1"]],[],{"1,1":[]},["1","1"])
	t.check(swapped.ok and not "0,0" in swapped.retired and w.diagnostics().dirty_chunks == 1,"dirty chunk pinned before staging")
	t.check(not w.acknowledge_staged(["0,0"],0).ok and w.acknowledge_staged(["0,0"],1).ok,"stale staging acknowledgment cannot drop newer changes")
	t.check("0,0" in w.prepare([["1","1"]],[],{"1,1":[]},["1","1"]).retired,"staged chunk can retire")
	var replay := {"0,0":[{"slot_id":prop.slot_id,"hp":2,"destroyed":false}]}
	w.prepare([["0","0"]],[],replay,["0","0"])
	t.check(w.chunk_at(Vector2(144,224)).props.filter(func(p): return p.slot_id == "nw_house")[0].hp == 2,"revisit restores partial damage")
	var peak := 0
	var valid := true
	for i in 10000:
		var origin := [str(i),str((i%17)-8)]
		var requested := [origin,[str(i+1),str((i%17)-7)]]
		var ready: Dictionary = w.prepare([requested[0]],[requested[1]],F.hydration(requested),origin)
		valid = valid and ready.ok and w.walkable(Vector2(384,384),32)
		peak = maxi(peak,w.diagnostics().resident_chunks)
		if i%100 == 0:
			var reverse: Dictionary = w.prepare([requested[1]],[requested[0]],F.hydration(requested),origin)
			valid = valid and reverse.ok
	t.check(valid and peak <= 64 and w.diagnostics().resident_props <= 768,"10000 chunks with winding reversals remain bounded")
	t.check(F.world().diagnostics().resident_chunks == 1,"fresh instances do not share caches")

	var full = F.world()
	var envelope: Array = []
	for y in range(-3,4):
		for x in range(-3,4): envelope.append([str(x),str(y)])
	t.check(full.prepare(envelope,[],F.hydration(envelope),["0","0"]).ok,"49 chunk envelope allowed when actually requested")
	var diagonal: Array = []
	for y in range(-2,5):
		for x in range(-2,5): diagonal.append([str(x),str(y)])
	t.check(full.prepare(diagonal,[],F.hydration(diagonal),["1","1"]).ok,"fast diagonal 49-chunk handover fits 62 pool slots")
	t.check(full.prepare(envelope,[],F.hydration(envelope),["0","0"]).ok and full.diagnostics().get("peak_pool_chunks",999) <= 64,"reverse seam includes transient handover budget")
	var distant: Array = []
	for y in range(17,24):
		for x in range(17,24): distant.append([str(x),str(y)])
	var over: Dictionary = full.prepare(distant,[],F.hydration(distant),["20","20"])
	t.check(not over.ok and over.error_code == "handover_capacity" and full.diagnostics().resident_chunks == 49,"oversized atomic handover requires preload/retirement scheduling")
	for radius in [8.0,16.0,18.0,20.0,24.0,28.0,30.0,32.0]: full.sweep(Vector2(16,200),Vector2(264,0),radius)
	t.check(full.diagnostics().get("clearance_cache_entries",-1) == 0,"exact expanded footprints are computed without retained geometry")

	var seams = F.world(F.neighborhood())
	for radius in [8.0,16.0,18.0,20.0,24.0,28.0,30.0,32.0]:
		for pair in [[Vector2(384,720),Vector2(0,96)],[Vector2(720,384),Vector2(96,0)],[Vector2(384,48),Vector2(0,-96)],[Vector2(48,384),Vector2(-96,0)]]:
			var crossing: Dictionary = seams.sweep(pair[0],pair[1],radius)
			t.check(crossing.ok and crossing.fraction == 1,"all-radius positive/negative cardinal port seams remain open")
	_hydration_boundary_regressions(t)
	_axis_slide_boundary_regression(t)

func _hydration_boundary_regressions(t) -> void:
	var cases := [
		{"name":"review_exact_probe","props":[{"slot_id":"bogus","hp":-1,"destroyed":false}],"error":"unknown_prop_slot"},
		{"name":"unknown_slot","props":[{"slot_id":"bogus","hp":2,"destroyed":false}],"error":"unknown_prop_slot"},
		{"name":"duplicate_slot","props":[{"slot_id":"nw_house","hp":2,"destroyed":false},{"slot_id":"nw_house","hp":1,"destroyed":false}],"error":"invalid_prop_delta"},
		{"name":"integer_record","props":[7],"error":"invalid_prop_delta"},
		{"name":"array_record","props":[[]],"error":"invalid_prop_delta"},
		{"name":"missing_hp","props":[{"slot_id":"nw_house","destroyed":false}],"error":"invalid_prop_delta"},
		{"name":"missing_destroyed","props":[{"slot_id":"nw_house","hp":2}],"error":"invalid_prop_delta"},
		{"name":"negative_hp","props":[{"slot_id":"nw_house","hp":-1,"destroyed":false}],"error":"invalid_prop_delta"},
		{"name":"above_catalog_hp","props":[{"slot_id":"nw_house","hp":4,"destroyed":false}],"error":"invalid_prop_delta"},
		{"name":"fractional_hp","props":[{"slot_id":"nw_house","hp":1.5,"destroyed":false}],"error":"invalid_prop_delta"},
		{"name":"nonfinite_hp","props":[{"slot_id":"nw_house","hp":INF,"destroyed":false}],"error":"invalid_prop_delta"},
		{"name":"zero_intact","props":[{"slot_id":"nw_house","hp":0,"destroyed":false}],"error":"invalid_prop_delta"},
		{"name":"positive_destroyed","props":[{"slot_id":"nw_house","hp":2,"destroyed":true}],"error":"invalid_prop_delta"},
		{"name":"nonboolean_destroyed","props":[{"slot_id":"nw_house","hp":2,"destroyed":0}],"error":"invalid_prop_delta"}
	]
	for mode in ["cold","resident_clean","resident_dirty"]:
		for invalid in cases:
			var world = F.world([["1","0"]] if mode == "cold" else [["0","0"]])
			if mode == "resident_dirty": world.apply_props([{"chunk":["0","0"],"props":[{"slot_id":"nw_house","hp":0,"destroyed":true}]}],1)
			var before: Dictionary = world.render_view()
			var counters: Dictionary = world.diagnostics()
			counters.erase("last_error")
			var hydration := {"-1,0":[],"0,0":invalid.props}
			var source := hydration.duplicate(true)
			# A valid cold chunk is processed before the invalid resident packet.
			var result: Dictionary = world.prepare([["-1","0"]],[["0","0"]],hydration,["0","0"])
			t.check(not result.ok and result.get("error_code") == invalid.error,"hydration fail-closed independent of residency: "+mode+"/"+invalid.name)
			t.check(result.activated.is_empty() and result.retired.is_empty() and world.render_view() == before,"rejected hydration cannot activate, retire, resurrect or rebase: "+mode+"/"+invalid.name)
			var after: Dictionary = world.diagnostics()
			after.erase("last_error")
			t.check(after == counters and hydration == source,"rejection preserves revisions, dirty pins, cache counters and input: "+mode+"/"+invalid.name)
	# Valid packet validation must not reapply older persisted geometry over live state.
	var live = F.world()
	live.apply_props([{"chunk":["0","0"],"props":[{"slot_id":"nw_house","hp":0,"destroyed":true}]}],1)
	var dirty_view: Dictionary = live.render_view()
	for prior in [[],[{"slot_id":"nw_house","hp":3,"destroyed":false}],[{"slot_id":"nw_house","hp":2,"destroyed":false}]]:
		var ready: Dictionary = live.prepare([["0","0"]],[],{"0,0":prior},["0","0"])
		t.check(ready.ok and live.render_view() == dirty_view and live.diagnostics().dirty_chunks == 1,"valid stale resident hydration is checked but does not replace live/dirty collapse")
	live.acknowledge_staged(["0,0"],1)
	var clean_ready: Dictionary = live.prepare([["0","0"]],[],{"0,0":[{"slot_id":"nw_house","hp":3,"destroyed":false}]},["0","0"])
	t.check(clean_ready.ok and live.render_view() == dirty_view and live.diagnostics().dirty_chunks == 0,"valid older hydration cannot replace live geometry after its dirty receipt is acknowledged")
	for boundary in [{"slot_id":"nw_house","hp":0,"destroyed":true},{"slot_id":"nw_house","hp":3,"destroyed":false}]:
		var cold = load("res://game/world/streamed_world.gd").new(F.generator(),42)
		var ready: Dictionary = cold.prepare([["0","0"]],[],{"0,0":[boundary]},["0","0"])
		t.check(ready.ok and cold.chunk_at(Vector2(144,224)).props.filter(func(p): return p.slot_id == "nw_house")[0].hp == boundary.hp,"cold hydration accepts exact catalog HP endpoints")

func _axis_slide_boundary_regression(t) -> void:
	var world = F.world(F.neighborhood())
	var start := Vector2(0,300)
	var delta := Vector2(300,-300)
	var straight: Dictionary = world.sweep(start,delta,8)
	var slide: Vector2 = world.move(start,delta,8)
	var horizontal: Dictionary = world.sweep(start,Vector2(delta.x,0),8)
	var vertical: Dictionary = world.sweep(horizontal.position,Vector2(0,delta.y),8)
	t.check(straight.position.is_equal_approx(Vector2(68,232)) and is_equal_approx(straight.fraction,68.0/300.0) and straight.hit_prop_id.ends_with(":nw_house"),"review diagonal straight sweep stops at exact house boundary")
	t.check(slide == Vector2(300,0) and slide == vertical.position and horizontal.fraction == 1 and vertical.fraction == 1,"move deliberately follows collision-safe X-then-Y slide segments, not the obstructed diagonal")
