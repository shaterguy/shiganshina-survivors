extends RefCounted
func run(t) -> void:
	var ui = load("res://game/ui/game_ui.gd").new()
	t.check(ui.has_method("development_notice"),"UI derives permanent notice from explicit dev-validation metadata")
	if not ui.has_method("development_notice"):
		ui.free()
		return
	var manifest := {"art_revision_status":{"final_export_allowed":false},"development_validation":{"mode":"development-validation","development_only":true}}
	var text: String = ui.development_notice(manifest)
	t.check(text.contains("미완료") and text.contains("5종") and text.contains("대체") and text.contains("보행"),"DEV notice explicitly reports incomplete art substitution and gait work")
	t.root.add_child(ui)
	ui._dev_notice.text = text
	ui.reflow(Vector2i(360,800),Rect2i(0,24,360,752))
	await t.process_frame
	await t.process_frame
	await t.process_frame
	t.check(ui._dev_notice.position.x+ui._dev_notice.size.x <= 340,"development banner fits narrow portrait safe width")
	t.check(ui._dev_notice.position.y+ui._dev_notice.size.y <= ui._hud.position.y,"development banner stays above combat HUD")
	t.check(ui._dev_notice.z_index > ui._overlay.z_index,"incomplete notice stays visible over menus")
	t.check(ui.development_notice({"art_revision_status":{"final_export_allowed":false}}).contains("수정 중"),"regular pending manifest retains art warning")
	t.check(ui.development_notice({"art_revision_status":{"final_export_allowed":true}}).is_empty(),"approved standard mode has no false dev substitution claim")
	ui.free()
