extends RefCounted
const UI = preload("res://game/ui/game_ui.gd")

func run(t) -> void:
	var ui := UI.new()
	t.root.add_child(ui)
	_selected_city_center(t,ui)
	_unselected_city(t,ui)
	_exact_rebase(t,ui)
	_distant_direction(t,ui)
	_authored_dock(t,ui)
	_final_boss(t,ui)
	await _final_layout(t,ui)
	ui.free()

func _state(origin: Array = ["0","0"], passage: Array = ["0","0"]) -> Dictionary:
	return {"phase":"evacuation","survival_tick":108000,"active_tick":108000,"final_started_tick":108000,"evacuation_ready":false,"pause_reasons":[],"player":{"hp":90,"max_hp":100,"xp":3,"level":2,"position":[384.0,384.0]},"stats":{"kills":4},"entities":[],"upgrade_offer":{},"escape_zone":[0,0,0,0],"world":{"mode":"streamed_city","stage":"city","origin_chunk":origin.duplicate(),"origin_revision":0,"evacuation":{"passage_id":"passage:city_v1:%s:%s" % passage,"chunk":passage.duplicate(),"selected_tick":108000}},"rules":{"enemy_catalog":{"armored_titan":{"name":"갑옷 거인"},"boss_charger":{"name":"돌진형 거인"}}}}

func _selected_city_center(t,ui) -> void:
	var state := _state(["1","-3"],["2","-3"])
	state.player.position = [-384.0,384.0]
	var before := state.duplicate(true)
	t.check(ui.objective_text(state) == "탈출 통로 → · 154","city target is selected absolute passage center, never inactive origin exit")
	ui.present(state)
	t.check(ui._objective.text == ui.objective_text(state),"visible objective uses selected passage guidance")
	t.check(not "남쪽" in ui._hud.text and "75초" in ui._hud.text,"city countdown never invents a southward dock destination")
	state.world.origin_chunk = ["2","-3"]
	state.player.position = [384.0,384.0]
	t.check(ui.objective_text(state) == "탈출 통로 ● · 도착","standing at selected passage center is an arrival")
	state.active_tick += 4499
	ui.present(state)
	t.check("1초" in ui._hud.text and not "대피 완료" in ui._hud.text,"countdown remains closed through tick 4499")
	state.active_tick += 1
	state.evacuation_ready = true
	ui.present(state)
	t.check("대피 완료" in ui._hud.text and not "남쪽" in ui._hud.text,"75 seconds opens escape while preserving actual objective")
	t.check(state.phase == "evacuation","presentation never awards a win without physical evacuation")
	ui.present(before)
	t.check(before == _state_with_position(["1","-3"],["2","-3"],[-384.0,384.0]),"present does not mutate passage identity or state")

func _state_with_position(origin: Array, passage: Array, position: Array) -> Dictionary:
	var state := _state(origin,passage)
	state.player.position = position
	return state

func _unselected_city(t,ui) -> void:
	for passage in [{},{"chunk":["0","0"]},{"passage_id":"passage:city_v1:1:0","chunk":["0","0"]},{"passage_id":"passage:city_v1:00:0","chunk":["00","0"]},{"passage_id":"passage:city_v1:9007199254740993:0","chunk":[9007199254740993,0]}]:
		var state := _state()
		state.world.evacuation = passage
		t.check(ui.objective_text(state) == "탈출 통로 준비 중","absent or inconsistent durable passage does not fabricate guidance: "+str(passage))
		ui.present(state)
		t.check(not "남쪽" in ui._hud.text and not "선착장" in ui._objective.text,"unselected city has no invented dock destination")

func _exact_rebase(t,ui) -> void:
	for entry in [
		{"origin":["9007199254740992","-9007199254740994"],"target":["9007199254740993","-9007199254740994"],"rebased":["9007199254740993","-9007199254740994"],"position":[-384.0,384.0],"expected":"탈출 통로 → · 77"},
		{"origin":["-9007199254740993","9007199254740994"],"target":["-9007199254740994","9007199254740994"],"rebased":["-9007199254740994","9007199254740994"],"position":[1152.0,384.0],"expected":"탈출 통로 ← · 77"},
		{"origin":["9223372036854775806","-9223372036854775808"],"target":["9223372036854775807","-9223372036854775808"],"rebased":["9223372036854775807","-9223372036854775808"],"position":[-384.0,384.0],"expected":"탈출 통로 → · 77"}
	]:
		var state := _state(entry.origin,entry.target)
		var passage: Dictionary = state.world.evacuation.duplicate(true)
		t.check(ui.objective_text(state) == entry.expected,"exact adjacent decimal addresses preserve direction and distance: "+str(entry.origin))
		state.world.origin_chunk = entry.rebased
		state.world.origin_revision += 1
		state.player.position = entry.position
		t.check(ui.objective_text(state) == entry.expected,"origin rebase preserves screen-independent passage guidance: "+str(entry.rebased))
		t.check(state.world.evacuation == passage,"guidance retains selected passage identity across rebase")

func _distant_direction(t,ui) -> void:
	for entry in [
		{"origin":["0","0"],"target":["20","0"],"arrow":"→"},
		{"origin":["0","0"],"target":["-20","0"],"arrow":"←"},
		{"origin":["0","0"],"target":["0","20"],"arrow":"↓"},
		{"origin":["0","0"],"target":["0","-20"],"arrow":"↑"},
		{"origin":["-9223372036854775808","9223372036854775807"],"target":["9223372036854775807","-9223372036854775808"],"arrow":"↗"},
		{"origin":["9223372036854775807","-9223372036854775808"],"target":["-9223372036854775808","9223372036854775807"],"arrow":"↙"},
		{"origin":["-9223372036854775808","-9223372036854775808"],"target":["9223372036854775807","9223372036854775807"],"arrow":"↘"},
		{"origin":["9223372036854775807","9223372036854775807"],"target":["-9223372036854775808","-9223372036854775808"],"arrow":"↖"}
	]:
		var state := _state(entry.origin,entry.target)
		t.check(ui.objective_text(state) == "탈출 통로 · 대략 "+entry.arrow,"distant passage compares exact signed chunks without overflow or false distance: "+str(entry.target))
	var edge := _state(["0","0"],["8","0"])
	t.check(ui.objective_text(edge) == "탈출 통로 → · 615","local working-set boundary keeps a real bounded distance")
	edge = _state(["0","0"],["9","0"])
	t.check(ui.objective_text(edge) == "탈출 통로 · 대략 →","one chunk beyond local working set has no invented distance")
	# Player local displacement participates even when one chunk axis is equal.
	var state := _state(["0","0"],["20","0"])
	state.player.position = [384.0,500.0]
	t.check(ui.objective_text(state) == "탈출 통로 · 대략 ↗","coarse sign includes same-chunk local direction")
	state.world.origin_chunk = ["1","1"]
	state.player.position = [-384.0,-268.0]
	t.check(ui.objective_text(state) == "탈출 통로 · 대략 ↗","coarse guidance stays invariant under a signed local rebase")

func _authored_dock(t,ui) -> void:
	var state := _state(["0","0"],["9007199254740993","0"])
	state.world.stage = "dock"
	state.world.escape_rect = [-56,320,112,80]
	state.player.position = [0.0,0.0]
	# The selected city passage is no longer the destination after transition.
	t.check(ui.objective_text(state) == "선착장 ↓ · 36","authored dock uses actual escape_rect instead of inactive city escape_zone")
	state.player.position = [0.0,360.0]
	t.check(ui.objective_text(state) == "선착장 ● · 도착","authored dock arrival remains physical exit center")
	state.erase("world")
	state.escape_zone = [-56,320,112,80]
	state.player.position = [0.0,0.0]
	t.check(ui.objective_text(state) == "선착장 ↓ · 36","finite authored regression retains existing exit guidance")

func _final_boss(t,ui) -> void:
	var state := _state()
	state.entities = [{"boss_id":"ch01_final_armored","enemy_id":"armored_titan","hp":999999.0,"max_hp":999999.0}]
	ui.present(state)
	t.check(not ui.get_node("BossHealth").visible,"invulnerable final Armored never advertises damageable health")
	t.check(ui._boss_name.visible and "갑옷 거인" in ui._boss_name.text and "탈출구 개방까지 75초" in ui._boss_name.text,"final actor name explains escape-opening survival objective")
	state.active_tick += 4500
	state.evacuation_ready = true
	ui.present(state)
	t.check(not ui.get_node("BossHealth").visible and "탈출구 개방" in ui._boss_name.text and not "75초" in ui._boss_name.text,"final threat label follows actual escape-opening time")
	state.entities = [{"boss_id":"ch01_b05","enemy_id":"boss_charger","hp":750.0,"max_hp":1000.0}]
	state.phase = "survival"
	ui.present(state)
	t.check(ui.get_node("BossHealth").visible and ui.get_node("BossHealth").value == 750 and ui.get_node("BossHealth").max_value == 1000,"ordinary boss HP bar remains unchanged after final threat presentation")
	t.check(ui._boss_name.text == "돌진형 거인","ordinary boss label remains unchanged")
	state.entities = []
	ui.present(state)
	t.check(not ui.get_node("BossHealth").visible and not ui._boss_name.visible,"no boss removes both threat and health display")

func _final_layout(t,ui) -> void:
	for screen in [Vector2i(360,800),Vector2i(450,800),Vector2i(800,450)]:
		var safe := Rect2i(0,24,screen.x,screen.y-48)
		ui.reflow(screen,safe)
		for elapsed in [0,4500]:
			var state := _state(["9223372036854775807","0"],["-9223372036854775808","0"])
			state.active_tick += elapsed
			state.evacuation_ready = elapsed == 4500
			state.entities = [{"boss_id":"ch01_final_armored","enemy_id":"armored_titan","hp":999999.0,"max_hp":999999.0}]
			ui.present(state)
			await t.process_frame
			await t.process_frame
			var bounds := Rect2(Vector2(safe.position),Vector2(safe.size))
			t.check(bounds.encloses(ui._boss_name.get_global_rect()),"final threat instruction fits actual safe area "+str(screen)+" tick "+str(elapsed))
			t.check(bounds.encloses(ui._hud.get_global_rect()) and bounds.encloses(ui._objective.get_global_rect()),"countdown and coarse destination fit actual safe area "+str(screen)+" tick "+str(elapsed))
			t.check(not ui._boss_name.get_global_rect().intersects(ui.get_node("Pause").get_global_rect()),"final threat instruction does not overlap pause control "+str(screen)+" tick "+str(elapsed))
