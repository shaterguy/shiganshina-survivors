extends RefCounted
func run(t) -> void:
	var path := "res://game/ui/game_ui.gd"
	t.check(FileAccess.file_exists(path), "GameUI exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	t.check(script != null and script.can_instantiate(), "GameUI compiles")
	if script == null or not script.can_instantiate(): return
	var ui = script.new()
	t.root.add_child(ui)
	ui.reflow(Vector2i(360,800),Rect2i(0,0,360,800))
	ui.present({})
	t.check(ui.get_node("Overlay/Panel/Body/ChoicesScroll/Choices").get_child_count() >= 1, "start menu has selectable action")
	var snapshot := {"phase":"survival","survival_tick":1200,"active_tick":1200,"pause_reasons":["upgrade"],"player":{"hp":90,"max_hp":100,"xp":3,"level":2},"stats":{"kills":4},"upgrade_offer":{"offer_id":"offer1","options":[{"option_id":"one","name":"쌍검 강화","description":"피해량 증가"},{"option_id":"two","name":"두 번째 선택","description":"이동 속도 증가"},{"option_id":"three","name":"매우 길어진 한국어 성장 선택지 설명을 안전하게 표시합니다","description":"공격 범위 증가"}],"selected_option_id":"two"}}
	var original := JSON.stringify(snapshot)
	ui.present(snapshot)
	t.check(ui.get_node("Overlay/Panel/Body/ChoicesScroll/Choices").get_child_count() == 3, "three upgrade options shown")
	t.check(ui.get_node("Overlay/Panel/Body/ChoicesScroll/Choices").columns == 1, "portrait stacks cards")
	ui.reflow(Vector2i(800,360),Rect2i(0,0,800,360))
	t.check(ui.get_node("Overlay/Panel/Body/ChoicesScroll/Choices").columns == 3, "landscape places cards across")
	t.check(JSON.stringify(snapshot) == original, "UI never mutates state")
	t.check(ui.get_node("Overlay/Panel/Body/ChoicesScroll").follow_focus, "layout scroll follows keyboard focus")
	ui.free()
