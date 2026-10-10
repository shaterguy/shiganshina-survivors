class_name GameUI
extends Control
const Progression = preload("res://game/progression/upgrade_catalog.gd")
signal upgrade_chosen(offer_id: String, option_id: String)
signal upgrade_focus_changed(option_id: String)
signal pause_changed(enabled: bool)
signal new_run_requested
signal resume_requested
signal settings_changed(values: Dictionary)
signal end_run_requested
signal touch_move_changed(vector: Vector2)
var _snapshot: Dictionary = {}
var _mode := ""
var _offer_id := ""
var _buttons: Array[Button] = []
var _focus_index := 0
var _touch_id := -1
var _touch_origin := Vector2.ZERO
var _screen_size := Vector2i(800,450)
var _safe_rect := Rect2i(0,0,800,450)
var _panel: PanelContainer
var _choices: GridContainer
var _scroll: ScrollContainer
var _title: Label
var _subtitle: Label
var _hud: Label
var _health: ProgressBar
var _xp: ProgressBar
var _boss_health: ProgressBar
var _boss_name: Label
var _stick_base: TextureRect
var _stick_knob: TextureRect
var _touch_vector := Vector2.ZERO
var _input_kind := "touch"
var _overlay: ColorRect
var _hint: Label
var _objective: Label
var _notice: Label
var _dev_notice: Label
var _checkpoint_available := false
var _settings_open := false
var _art: Dictionary = {}
var _layout_generation := 0
var _settings := {"deadzone":0.20,"audio_master":0.8,"screen_shake":0.4,"reduce_effects":false}
func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	if manifest is Dictionary: _art = manifest.get("assets",{})
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Noto Sans CJK KR", "Noto Sans", "sans-serif"])
	add_theme_font_override("font",font)
	add_theme_font_size_override("font_size",16)
	_hud = Label.new()
	_hud.name = "HUD"
	_hud.position = Vector2(20,14)
	_hud.add_theme_color_override("font_color",Color("f1e7cf"))
	add_child(_hud)
	_health = ProgressBar.new()
	_health.position = Vector2(20,48)
	_health.size = Vector2(200,10)
	_health.show_percentage = false
	add_child(_health)
	_bar_colors(_health,Color("b9544f"))
	_xp = ProgressBar.new()
	_xp.name = "XP"
	_xp.show_percentage = false
	_xp.size = Vector2(200,6)
	_bar_colors(_xp,Color("73b8bb"))
	add_child(_xp)
	_boss_health = ProgressBar.new()
	_boss_health.name = "BossHealth"
	_boss_health.show_percentage = false
	_bar_colors(_boss_health,Color("cf6e46"))
	add_child(_boss_health)
	_boss_name = Label.new()
	_boss_name.add_theme_font_size_override("font_size",13)
	_boss_name.add_theme_color_override("font_color",Color("f4c36b"))
	add_child(_boss_name)
	_stick_base = TextureRect.new()
	_stick_base.name = "TouchBase"
	_stick_base.texture = _art_texture("ui_stick_base")
	_stick_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_base.modulate.a = 0.5
	add_child(_stick_base)
	_stick_knob = TextureRect.new()
	_stick_knob.name = "TouchKnob"
	_stick_knob.texture = _art_texture("ui_stick_knob")
	_stick_knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stick_knob.modulate.a = 0.7
	add_child(_stick_knob)
	var pause := Button.new()
	pause.text = "Ⅱ"
	pause.name = "Pause"
	pause.custom_minimum_size = Vector2(48,48)
	pause.pressed.connect(func(): pause_changed.emit(true))
	add_child(pause)
	_hint = Label.new()
	_hint.text = "왼쪽 아래를 드래그해 이동 · 자동 공격"
	_hint.add_theme_color_override("font_color",Color("e9d5af"))
	_hint.add_theme_font_size_override("font_size",13)
	add_child(_hint)
	_objective = Label.new()
	_objective.add_theme_font_size_override("font_size",13)
	_objective.add_theme_color_override("font_color",Color("e6c88d"))
	add_child(_objective)
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size",12)
	_notice.add_theme_color_override("font_color",Color("f4c36b"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_notice)
	_dev_notice = Label.new()
	_dev_notice.text = development_notice(manifest if manifest is Dictionary else {})
	_dev_notice.add_theme_font_size_override("font_size",11)
	_dev_notice.add_theme_color_override("font_color",Color("f4c36b"))
	_dev_notice.z_index = 3
	add_child(_dev_notice)
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.color = Color(0.025,0.035,0.03,0.91)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)
	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_overlay.add_child(_panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("18211d")
	style.border_color = Color("a18452")
	style.set_border_width_all(2)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	_panel.add_theme_stylebox_override("panel",_art_style("panel_default",style))
	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation",14)
	_panel.add_child(body)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size",28)
	_title.add_theme_color_override("font_color",Color("e6c88d"))
	body.add_child(_title)
	_subtitle = Label.new()
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_subtitle)
	_choices = GridContainer.new()
	_choices.name = "Choices"
	_choices.add_theme_constant_override("h_separation",10)
	_choices.add_theme_constant_override("v_separation",10)
	_scroll = ScrollContainer.new()
	_scroll.name = "ChoicesScroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.custom_minimum_size = Vector2(0,60)
	body.add_child(_scroll)
	_choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_choices)
	reflow(_screen_size, Rect2i(Vector2i.ZERO,_screen_size))
	present({})
func reflow(size_px: Vector2i, safe_rect_px: Rect2i) -> void:
	_screen_size = size_px
	_safe_rect = safe_rect_px
	size = Vector2(size_px)
	if not is_instance_valid(_panel): return
	_overlay.size = size
	var safe := Rect2(Vector2(safe_rect_px.position), Vector2(safe_rect_px.size))
	var width := minf(730 if _mode == "upgrade" else 520, safe.size.x - 32)
	var desired_height := 490 if _mode == "settings" else ((600 if _screen_size.y > _screen_size.x else 390) if _mode == "upgrade" else (390 if _mode in ["title","pause"] else 310))
	var height := minf(desired_height, safe.size.y - 36)
	_panel.size = Vector2(width,height)
	_panel.position = safe.position + (safe.size-_panel.size)*0.5
	_layout_generation += 1
	call_deferred("_settle_panel",_layout_generation)
	_choices.columns = 3 if size_px.x > size_px.y and _mode == "upgrade" else 1
	get_node("Pause").position = safe.position + Vector2(safe.size.x-62,10)
	_hud.position = safe.position + Vector2(20,20)
	_health.position = safe.position + Vector2(20,50)
	_health.size = Vector2(200,10)
	_xp.position = safe.position + Vector2(20,65)
	var boss_left := safe.position+Vector2(20,86) if size_px.y > size_px.x else safe.position+Vector2(safe.size.x*0.5+12,24)
	_boss_name.position = boss_left
	_boss_health.position = boss_left+Vector2(0,22)
	_boss_health.size = Vector2(minf(250,safe.size.x-100),7)
	_objective.position = safe.position + Vector2(20,120)
	if _notice.get_parent() == self:
		_notice.position = safe.position + Vector2(20,145)
		_notice.size = Vector2(safe.size.x-40,40)
	_notice.z_index = 2
	_hint.position = safe.position + Vector2(20,safe.size.y-28)
	_dev_notice.position = safe.position + Vector2(20,2)
	cancel_touch()
func present(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	_objective.text = objective_text(snapshot)
	_objective.visible = not snapshot.is_empty()
	_hud.visible = not snapshot.is_empty()
	_health.visible = not snapshot.is_empty()
	_xp.visible = not snapshot.is_empty()
	_boss_health.visible = false
	_boss_name.visible = false
	get_node("Pause").visible = not snapshot.is_empty()
	var mode := "title"
	if not snapshot.is_empty():
		var seconds := int(snapshot.survival_tick)/60
		_hud.text = "%02d:%02d  •  LV %d  •  %d 처치" % [seconds/60,seconds%60,snapshot.player.level,snapshot.stats.get("kills",0)]
		_health.max_value = snapshot.player.max_hp
		_health.value = snapshot.player.hp
		_xp.max_value = Progression.xp_to_next(int(snapshot.player.level),snapshot.get("rules",{}).get("progression",{"base_xp":8,"xp_per_level":4}))
		_xp.value = snapshot.player.get("xp",0)
		for entity in snapshot.get("entities",[]):
			if str(entity.get("boss_id","")).is_empty(): continue
			_boss_health.visible = true
			_boss_name.visible = true
			_boss_health.max_value = entity.max_hp
			_boss_health.value = entity.hp
			_boss_name.text = snapshot.get("rules",{}).get("enemy_catalog",{}).get(entity.enemy_id,{}).get("name","강적")
			break
		mode = "play"
		if snapshot.phase in ["won","dead"]: mode = snapshot.phase
		elif not snapshot.get("upgrade_offer",{}).is_empty(): mode = "upgrade"
		elif not snapshot.pause_reasons.is_empty(): mode = "pause"
		if snapshot.phase == "evacuation":
			var remaining := maxi(0,75-int((int(snapshot.active_tick)-int(snapshot.final_started_tick))/60))
			_hud.text = "주민 대피 %d초 · 남쪽 선착장으로" % remaining if remaining > 0 else "대피 완료 · 남쪽 선착장으로 탈출!"
	if _settings_open: mode = "settings"
	_stick_base.visible = mode == "play" and _input_kind != "gamepad"
	_stick_knob.visible = _stick_base.visible
	_update_stick()
	var offer_id: String = snapshot.get("upgrade_offer",{}).get("offer_id","")
	_notice.visible = not _notice.text.is_empty()
	var notice_parent: Node = self if mode == "play" else _panel.get_node("Body")
	if _notice.get_parent() != notice_parent:
		_notice.reparent(notice_parent)
		if notice_parent != self: notice_parent.move_child(_notice,2)
	if mode == _mode and offer_id == _offer_id: return
	_mode = mode
	_offer_id = offer_id
	_overlay.visible = mode != "play"
	_overlay.color.a = 0.42 if mode == "title" else 0.82
	for button in _buttons:
		_choices.remove_child(button)
		button.queue_free()
	_buttons.clear()
	_focus_index = 0
	match mode:
		"title":
			_title.text = "시간시나 생존전"
			_subtitle.text = "CHAPTER 01 · 845\n성벽은 무너졌다. 주민이 떠날 때까지 버텨라.\n30분 생존 · 다섯 강적 · 마지막 탈출"
			if _checkpoint_available: _add_button("이어서 출격",func(): resume_requested.emit())
			_add_button("새로 출격" if _checkpoint_available else "출격",func(): new_run_requested.emit())
			_add_button("설정",open_settings)
		"upgrade":
			_title.text = "전열을 가다듬어라"
			_subtitle.text = "성장 하나를 선택하세요. 선택하는 동안 전투는 멈춥니다."
			for option in snapshot.upgrade_offer.options:
				var id := str(option.option_id)
				var button := _add_button(str(option.name)+"\n"+str(option.get("description","")),func(): upgrade_chosen.emit(offer_id,id))
				button.icon = _art_texture(_item_icon(str(option.get("item_id",""))))
				button.custom_minimum_size.y = 130 if _screen_size.y > _screen_size.x else 190
				button.add_theme_constant_override("icon_max_width",32)
				button.focus_entered.connect(func(): upgrade_focus_changed.emit(id))
				if id == snapshot.upgrade_offer.get("selected_option_id",""): _focus_index = _buttons.size()-1
		"pause":
			_title.text = "잠시 숨을 고르자"
			_subtitle.text = "전투와 생존 시간이 정지했습니다."
			_add_button("계속",func(): resume_requested.emit())
			_add_button("설정",open_settings)
			_add_button("이번 판 종료",_confirm_end)
		"settings":
			_title.text = "설정"
			_subtitle.text = "A 또는 터치로 변경 · B 뒤로"
			_add_button("스틱 데드존 %d%%" % roundi(_settings.deadzone*100),func(): _cycle_setting("deadzone",0.05,0.10,0.35))
			_add_button("음량 %d%%" % roundi(_settings.audio_master*100),func(): _cycle_setting("audio_master",0.2,0.0,1.0))
			_add_button("화면 흔들림 %d%%" % roundi(_settings.screen_shake*100),func(): _cycle_setting("screen_shake",0.2,0.0,1.0))
			_add_button("효과 감소: " + ("켜짐" if _settings.reduce_effects else "꺼짐"),func():
				_settings.reduce_effects = not _settings.reduce_effects
				_publish_settings())
			_add_button("뒤로",close_settings)
		"won","dead":
			_title.text = "주민 대피 완료" if mode == "won" else "끝까지 싸웠다"
			_subtitle.text = "당신이 확보한 시간이 생명을 구했습니다." if mode == "won" else "다른 성장 조합으로 다시 도전하세요."
			_add_button("다시 출격",func(): new_run_requested.emit())
	reflow(_screen_size,_safe_rect)
	if not _buttons.is_empty(): _buttons[_focus_index].grab_focus()
func _add_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	for state_name in ["normal","hover","focus","pressed","disabled"]:
		var art_id := "panel_focus" if state_name in ["hover","focus"] else ("panel_pressed" if state_name == "pressed" else ("panel_disabled" if state_name == "disabled" else "panel_default"))
		var style := _art_style(art_id)
		if style != null: button.add_theme_stylebox_override(state_name,style)
	button.add_theme_color_override("font_color",Color("f0dfba"))
	button.custom_minimum_size = Vector2(0,56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.pressed.connect(action)
	_choices.add_child(button)
	_buttons.append(button)
	button.focus_entered.connect(func(): _focus_index = _buttons.find(button))
	return button
func navigate(action: String) -> void:
	if action in ["pause","cancel"]:
		if _settings_open:
			close_settings()
			return
		if _mode == "play": pause_changed.emit(true)
		elif _mode == "pause": resume_requested.emit()
		return
	if _buttons.is_empty(): return
	if action in ["down","right"]: _focus_index = (_focus_index+1)%_buttons.size()
	elif action in ["up","left"]: _focus_index = posmod(_focus_index-1,_buttons.size())
	elif action == "accept": _buttons[_focus_index].pressed.emit()
	if not _buttons.is_empty(): _buttons[_focus_index].grab_focus()
func _confirm_end() -> void:
	_subtitle.text = "이번 판을 종료할까요? 진행 중인 전투는 끝납니다."
	_buttons[0].text = "계속 싸우기"
	_buttons[-1].text = "종료 확인"
	_buttons[-1].pressed.disconnect(_confirm_end)
	_buttons[-1].pressed.connect(func(): end_run_requested.emit())
func set_settings(values: Dictionary) -> void:
	_settings.merge(values,true)
func open_settings() -> void:
	_settings_open = true
	present(_snapshot)
func close_settings() -> void:
	_settings_open = false
	present(_snapshot)
func _cycle_setting(key: String, increment: float, low: float, high: float) -> void:
	var next := float(_settings[key]) + increment
	_settings[key] = low if next > high+0.00001 else snappedf(next,increment)
	_publish_settings()
func _publish_settings() -> void:
	settings_changed.emit(_settings.duplicate(true))
	var previous_focus := _focus_index
	_mode = ""
	present(_snapshot)
	_focus_index = mini(previous_focus,_buttons.size()-1)
	_buttons[_focus_index].grab_focus()
func set_checkpoint_available(available: bool) -> void:
	if _checkpoint_available == available: return
	_checkpoint_available = available
	_mode = ""
	present(_snapshot)
func set_save_notice(message: String) -> void:
	if is_instance_valid(_notice):
		_notice.text = message
		_notice.visible = not message.is_empty()
func set_input_hint(kind: String) -> void:
	_input_kind = kind
	_hint.text = "스틱/D-pad 이동 · A 확인 · B 뒤로 · Menu 일시정지" if kind == "gamepad" else "왼쪽 아래를 드래그해 이동 · 자동 공격"
func _input(event: InputEvent) -> void:
	if _mode != "play": return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1 and event.position.x < size.x*0.55 and event.position.y > size.y*0.4:
			_touch_id = event.index
			_touch_origin = event.position
			_update_stick()
		elif not event.pressed and event.index == _touch_id: cancel_touch()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_set_touch_vector((event.position-_touch_origin)/60.0)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and event.position.x < size.x*0.55 and event.position.y > size.y*0.4:
			_touch_id = 99
			_touch_origin = event.position
			_update_stick()
		elif not event.pressed: cancel_touch()
	elif event is InputEventMouseMotion and _touch_id == 99:
		_set_touch_vector((event.position-_touch_origin)/60.0)
func cancel_touch() -> void:
	_touch_id = -1
	_set_touch_vector(Vector2.ZERO)

func _art_texture(id: String) -> Texture2D:
	if not _art.has(id) or not ResourceLoader.exists(_art[id].path): return null
	return load(_art[id].path) as Texture2D
func _art_style(id: String, fallback: StyleBox = null) -> StyleBox:
	var texture := _art_texture(id)
	if texture == null: return fallback
	var style := StyleBoxTexture.new()
	style.texture = texture
	var margins: Array = _art[id].get("patch_margin_px",[12,12,12,12])
	for side in range(4): style.set_texture_margin(side,float(margins[side]))
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
func _item_icon(id: String) -> String:
	return {"blade_slash":"icon_twin_blades","spin_slash":"icon_spin_slash","odm_dash":"icon_omni_dash","reentry_combo":"icon_reentry_combo","wall_cannon":"icon_wall_cannon","ally_cover":"icon_ally_cover","damage":"icon_damage","fire_interval":"icon_cooldown","movement":"icon_movement","max_health":"icon_health","recovery":"icon_regeneration","pickup":"icon_pickup","range":"icon_range","armor":"icon_armor"}.get(id,"")

func _settle_panel(generation: int) -> void:
	await get_tree().process_frame
	if generation != _layout_generation or not is_instance_valid(_panel): return
	var safe := Rect2(Vector2(_safe_rect.position),Vector2(_safe_rect.size))
	var width := minf(730 if _mode == "upgrade" else 520,safe.size.x-32)
	var desired_height := 490 if _mode == "settings" else ((600 if _screen_size.y > _screen_size.x else 390) if _mode == "upgrade" else (390 if _mode in ["title","pause"] else 310))
	# After width propagation, wrapped text has its real minimum height.
	_panel.size = Vector2(width,minf(desired_height,safe.size.y-36))
	_panel.position = safe.position + (safe.size-_panel.size)*0.5

func _set_touch_vector(value: Vector2) -> void:
	_touch_vector = value.limit_length()
	touch_move_changed.emit(_touch_vector)
	_update_stick()
func _update_stick() -> void:
	if not is_instance_valid(_stick_base): return
	var origin := _touch_origin if _touch_id >= 0 else Vector2(_safe_rect.position)+Vector2(82,_safe_rect.size.y-94)
	_stick_base.position = origin-Vector2(48,48)
	_stick_knob.position = origin+_touch_vector*36-Vector2(20,20)
func _bar_colors(bar: ProgressBar, color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("20272b")
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background",background)
	bar.add_theme_stylebox_override("fill",fill)

func objective_text(snapshot: Dictionary) -> String:
	if snapshot.is_empty() or snapshot.get("phase","") in ["won","dead"]: return ""
	var player: Array = snapshot.player.position if snapshot.player.has("position") else [0,0]
	if snapshot.phase == "evacuation":
		var zone: Array = snapshot.escape_zone
		var offset := Vector2(zone[0]+zone[2]/2-player[0],zone[1]+zone[3]/2-player[1])
		return "선착장 " + _direction_label(offset) + (" · 도착" if offset.length() < 40 else " · %d" % ceili(offset.length()/10))
	for entity in snapshot.get("entities",[]):
		if not str(entity.get("boss_id","")).is_empty() and entity.has("position"):
			return "강적 " + _direction_label(Vector2(entity.position[0]-player[0],entity.position[1]-player[1]))
	var next_tick := 108000
	for tick in [18000,36000,54000,72000,90000,108000]:
		if tick > int(snapshot.survival_tick):
			next_tick = tick
			break
	var seconds := ceili(float(maxi(0,next_tick-int(snapshot.survival_tick)))/60.0)
	return ("최종 대피까지 " if next_tick == 108000 else "다음 강적까지 ") + "%02d:%02d" % [seconds/60,seconds%60]
func _direction_label(offset: Vector2) -> String:
	if offset.length() < 8: return "●"
	return ["→","↘","↓","↙","←","↖","↑","↗"][posmod(roundi(offset.angle()/(PI/4)),8)]

func development_notice(manifest: Dictionary) -> String:
	var development = manifest.get("development_validation",{})
	if development is Dictionary and development.get("mode","") == "development-validation" and development.get("development_only",false):
		return "DEV 미완료 · 5종 기본 외형 대체 · 보행 수정 중"
	if not manifest.get("art_revision_status",{}).get("final_export_allowed",true):
		return "개발 검증판 · 일부 거인 외형과 동작 수정 중"
	return ""
