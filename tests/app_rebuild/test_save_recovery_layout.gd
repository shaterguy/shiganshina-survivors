extends RefCounted
# Headless Control geometry only; parent owns actual-window readability checks.
const Recovery = preload("res://tests/app_rebuild/test_save_recovery_ui.gd")
func run(t) -> void:
	var fixture := Recovery.new()._incompatible_fixture(t,true)
	var app = Recovery.new()._restart_observed(t,fixture.directory)
	app.ui.set_save_notice("QA 전용 복구 화면 · 기존 사용자 저장은 사용하지 않습니다.")
	app.ui.reflow(Vector2i(800,450),Rect2i(0,0,800,450))
	await t.process_frame
	await t.process_frame
	await t.process_frame
	var panel: Rect2 = app.ui._panel.get_global_rect()
	var scroll: Rect2 = app.ui._scroll.get_global_rect()
	t.check(panel.position.y >= 0 and panel.end.y <= 450,"landscape recovery panel fits safe viewport after wrapped-text layout")
	t.check(scroll.encloses(app.ui._buttons[0].get_global_rect()) and scroll.encloses(app.ui._buttons[1].get_global_rect()),"landscape recovery shows safe keep and explicit preserved-start actions together")
	app.free()
