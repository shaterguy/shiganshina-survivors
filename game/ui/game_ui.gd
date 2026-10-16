class_name GameUI
extends Control
const Loot = preload("res://game/loot/loot_rules.gd")
const RewardFeedback = preload("res://game/ui/reward_feedback.gd")
var _reward_feedback: Control
const TOUCH_RADIUS := 36.0
const TOUCH_DEADZONE := 4.0 / TOUCH_RADIUS
const MOUSE_POINTER_ID := -2 # Touch indices are nonnegative; -1 means no owner.
const Progression = preload("res://game/progression/upgrade_catalog.gd")
const Address = preload("res://game/world/world_address.gd")
const Signature = preload("res://game/combat/character_skill_resolver.gd")
const OwnedHUD = preload("res://game/ui/progression_hud.gd")
const Card = preload("res://game/ui/growth_card.gd")
const Icons = preload("res://game/ui/skill_icons.gd")
const DetailPanel = preload("res://game/ui/evolution_detail_panel.gd")
const ShopPanel = preload("res://game/ui/supply_shop_panel.gd")
const PreparationPanel = preload("res://game/ui/loadout_panel.gd")
const Characters = preload("res://game/progression/character_catalog.gd")
signal audio_requested(id: String)
signal upgrade_chosen(offer_id: String, option_id: String)
signal upgrade_focus_changed(option_id: String)
signal pause_changed(enabled: bool)
signal new_run_requested
signal new_run_replacement_confirmed(run_id: String)
signal resume_requested
signal settings_changed(values: Dictionary)
signal end_run_requested
signal touch_move_changed(vector: Vector2)
signal shop_open_requested
signal shop_closed
signal purchase_requested(item_id: String, view_revision: int)
signal loadout_changed(selection: Dictionary, view_revision: int)
signal character_selected(character_id: String, view_revision: int)
signal run_start_requested
signal recovery_start_requested
signal recovery_keep_requested
signal recovery_retry_requested
signal recovery_continue_requested
signal recovery_supply_toggled
var _recovery_view: Dictionary = {}
var _snapshot: Dictionary = {}
var _growth_view: Dictionary = {}
var _supply_view: Dictionary = {}
var _supply_mode := ""
var _supply_panel: Control
var _supply_origin_focus := ""
var _supply_locked := false
var _supply_waiting_result := false
var _supply_lock_revision := -1
var _last_action_result: Dictionary = {}
var _modal_focus := {"shop":"","loadout":""}
var _owned_open := false
var _detail_origin := "upgrade"
var _detail_id := ""
var _return_focus_id := ""
var _accept_transition_gate := false
var _dispatching_accept := false
var _target_button: Button
var _mode := ""
var _offer_id := ""
var _buttons: Array[Button] = []
# Three UI-local slots are attached once, before any authored offer is shown.
var _growth_groups: Array[VBoxContainer] = []
var _growth_cards: Array[Button] = []
var _growth_details: Array[Button] = []
var _growth_generation := 0
var _focus_index := 0
var _touch_id := -1
var _touch_origin := Vector2.ZERO
var _screen_size := Vector2i(800,450)
var _safe_rect := Rect2i(0,0,800,450)
var _panel: PanelContainer
var _growth_layout_queued := false
var _choices: GridContainer
var _scroll: ScrollContainer
var _title: Label
var _subtitle: Label
var _owned_hud: Control
var _loot_hud: Label
var _xp_feedback_run := ""
var _xp_feedback_seq := 0
var _xp_feedback_amount := 0
var _xp_feedback_seconds := 0.0
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
var _growth_notice: Label
var _growth_notice_text := ""
var _growth_notice_seconds := 0.0
var _growth_waiting_result := false
var _notice: Label
var _dev_notice: Label
var _checkpoint_available := false
var _checkpoint_run_id := ""
var _scenario_page := ""
var _new_run_waiting := false
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
	theme = preload("res://game/ui/korean_ui_theme.tres")
	add_theme_font_size_override("font_size",16)
	_hud = Label.new()
	_hud.name = "HUD"
	_hud.add_theme_font_size_override("font_size",13)
	_hud.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_boss_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_owned_hud = OwnedHUD.new()
	_owned_hud.name = "ProgressionHUD"
	add_child(_owned_hud)
	_owned_hud.details_requested.connect(func():
		audio_requested.emit("select")
		open_owned_skills())
	var pause := Button.new()
	pause.text = "Ⅱ"
	pause.name = "Pause"
	pause.custom_minimum_size = Vector2(48,48)
	pause.pressed.connect(func():
		audio_requested.emit("cancel")
		pause_changed.emit(true))
	add_child(pause)
	_hint = Label.new()
	_hint.text = ""
	_hint.add_theme_color_override("font_color",Color("e9d5af"))
	_hint.add_theme_font_size_override("font_size",13)
	add_child(_hint)
	_objective = Label.new()
	_objective.add_theme_font_size_override("font_size",13)
	_objective.add_theme_color_override("font_color",Color("e6c88d"))
	_objective.add_theme_color_override("font_shadow_color",Color("18211d"))
	_objective.add_theme_constant_override("shadow_offset_x",1)
	_objective.add_theme_constant_override("shadow_offset_y",1)
	_objective.add_theme_constant_override("shadow_outline_size",0)
	add_child(_objective)
	_loot_hud = Label.new()
	_loot_hud.name = "LootHUD"
	_loot_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loot_hud.add_theme_font_size_override("font_size",11)
	_loot_hud.add_theme_color_override("font_color",Color("f4c36b"))
	add_child(_loot_hud)
	_reward_feedback = RewardFeedback.new()
	_reward_feedback.name = "RewardFeedback"
	add_child(_reward_feedback)
	_notice = Label.new()
	_notice.add_theme_font_size_override("font_size",12)
	_notice.add_theme_color_override("font_color",Color("f4c36b"))
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_notice)
	_growth_notice = Label.new()
	_growth_notice.name = "ConfirmedUpgrade"
	_growth_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_growth_notice.add_theme_font_size_override("font_size",13)
	_growth_notice.add_theme_color_override("font_color",Color("f4c36b"))
	_growth_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_growth_notice.hide()
	add_child(_growth_notice)
	set_process(false)
	_dev_notice = Label.new()
	_dev_notice.text = development_notice(manifest if manifest is Dictionary else {})
	_dev_notice.tooltip_text = _dev_notice.text
	_dev_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	_target_button = Button.new()
	_target_button.name = "EvolutionTarget"
	_target_button.custom_minimum_size = Vector2(0,48)
	_target_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target_button.button_down.connect(func(): _target_button.set_meta("growth_press_generation",_growth_generation))
	_target_button.pressed.connect(func():
		if _consume_growth_press(_target_button):
			audio_requested.emit("select")
			open_evolution_details(str(_growth_view.get("target",{}).get("evolution_id",""))))
	_target_button.hide()
	body.add_child(_target_button)
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
	_prepare_growth_controls()
	reflow(_screen_size, Rect2i(Vector2i.ZERO,_screen_size))
	present({})
func reflow(size_px: Vector2i, safe_rect_px: Rect2i) -> void:
	var geometry_changed := size_px != _screen_size or safe_rect_px != _safe_rect
	_screen_size = size_px
	_safe_rect = safe_rect_px
	size = Vector2(size_px)
	if not is_instance_valid(_panel): return
	_overlay.size = size
	var safe := Rect2(Vector2(safe_rect_px.position), Vector2(safe_rect_px.size))
	var width := _menu_width(safe.size.x)
	if geometry_changed and _mode == "upgrade":
		_prepare_growth_widths(_growth_view.get("active_offer",{}).get("options",[]).size())
	var desired_height := 490 if _mode == "settings" else ((650 if _screen_size.y > _screen_size.x else 410) if _mode in ["upgrade","shop","loadout","owned_skills","evolution_detail","save_recovery"] else (430 if _mode in ["title","pause","scenario_select","scenario_briefing","new_run_confirm"] else 310))
	var short_supply := _mode in ["shop","loadout"] and _screen_size.x > _screen_size.y and safe.size.y < 360
	var height := minf(desired_height, safe.size.y - (12 if short_supply else (32 if _mode == "shop" else 36)))
	if _mode == "shop":
		_subtitle.text = "전투 종료 정산 금화"+(" · " if short_supply else "\n")+"A 확인 · B 뒤로"
	if _mode == "loadout":
		_subtitle.text = "시나리오 1 · %s · 845" % _chapter_title()+(" · " if short_supply else "\n")+"A 선택 · B 상점"
	if _mode == "upgrade": _subtitle.text = _growth_subtitle()
	_sync_upgrade_notice(_mode)
	if short_supply: _subtitle.add_theme_font_size_override("font_size",13)
	else: _subtitle.remove_theme_font_size_override("font_size")
	_panel.size = Vector2(width,height)
	_panel.position = safe.position + (safe.size-_panel.size)*0.5
	_layout_generation += 1
	call_deferred("_queue_settle_panel",_layout_generation)
	_choices.columns = _menu_columns()
	# Keep the choice viewport large enough for the summary itself. Full recipe
	# prose belongs to the explicit detail view, never an oversized focus target.
	var compact_menu := _mode in ["title","pause","settings","won","dead","abandoned","scenario_select","scenario_briefing","new_run_confirm"]
	_panel.get_node("Body").add_theme_constant_override("separation",4 if short_supply else (8 if _mode in ["upgrade","shop"] or compact_menu else 14))
	_choices.add_theme_constant_override("v_separation",6 if compact_menu else 10)
	_title.add_theme_font_size_override("font_size",20 if short_supply else (24 if _mode in ["upgrade","shop"] else 28))
	get_node("Pause").position = safe.position + Vector2(safe.size.x-54,2)
	var portrait := size_px.y > size_px.x
	_owned_hud.position = safe.position+Vector2(4,52) if portrait else safe.position+Vector2(198,20)
	var signature_height := 24 if _owned_hud.signature_visible() else 0
	_owned_hud.reflow(Vector2(safe.size.x-8 if portrait else safe.size.x-266,108+signature_height))
	_hud.position = safe.position + Vector2(8,19)
	_hud.size = Vector2(minf(184,safe.size.x-70),19)
	_health.position = safe.position + Vector2(8,40)
	_health.size = Vector2(176,4)
	_xp.position = safe.position + Vector2(8,46)
	_xp.size = Vector2(176,3)
	var boss_left := safe.position+Vector2(8,194+signature_height) if portrait else safe.position+Vector2(8,92)
	_boss_name.position = boss_left
	_boss_name.size = Vector2(safe.size.x-16 if portrait else 176,20)
	_boss_health.position = boss_left+Vector2(0,22)
	_boss_health.size = Vector2(minf(250,safe.size.x-100) if portrait else 176,7)
	_objective.position = safe.position + Vector2(8,162+signature_height if portrait else 52)
	_loot_hud.position = _objective.position+Vector2(0,18)
	_loot_hud.size = Vector2(safe.size.x-16 if portrait else 176,16)
	if is_instance_valid(_reward_feedback):
		_reward_feedback.size = Vector2(minf(320.0,safe.size.x-16.0),200.0)
		_reward_feedback.position = Vector2(safe.position.x+8.0,safe.end.y-350.0) if portrait else Vector2(safe.end.x-_reward_feedback.size.x-8.0,safe.position.y+48.0)
	if _notice.get_parent() == self:
		_notice.position = safe.position + Vector2(8,220+signature_height if portrait else 148+signature_height)
		_notice.size = Vector2(safe.size.x-40,40)
	_notice.z_index = 2
	if _growth_notice.get_parent() == self:
		_growth_notice.position = safe.position+Vector2(8,226+signature_height if portrait else 148+signature_height)
		_growth_notice.size = Vector2(safe.size.x-16,44)
	_growth_notice.z_index = 2
	_hint.position = safe.position + Vector2(20,safe.size.y-28)
	_dev_notice.position = safe.position + Vector2(8,2)
	_dev_notice.size = Vector2(safe.size.x-72,16)
	cancel_touch()
func present(snapshot: Dictionary) -> void:
	if _snapshot.get("run_id","") != snapshot.get("run_id",""): reset_progression_feedback()
	if _xp_feedback_run != snapshot.get("run_id",""):
		_xp_feedback_run = snapshot.get("run_id","")
		_xp_feedback_seq = 0
		_xp_feedback_amount = 0
		_xp_feedback_seconds = 0.0
	_reward_feedback.sync_snapshot(snapshot)
	_snapshot = snapshot.duplicate(true)
	if _owned_hud.present_signature(Signature.presentation(snapshot)): reflow(_screen_size,_safe_rect)
	_objective.text = objective_text(snapshot)
	_objective.visible = not snapshot.is_empty()
	_hud.visible = not snapshot.is_empty()
	_owned_hud.visible = not snapshot.is_empty()
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
			var final_armored: bool = entity.get("boss_id","") == "ch01_final_armored" and entity.get("enemy_id","") == "armored_titan"
			_boss_health.visible = not final_armored
			_boss_name.visible = true
			_boss_name.text = snapshot.get("rules",{}).get("enemy_catalog",{}).get(entity.enemy_id,{}).get("name","강적")
			if final_armored:
				var remaining := _evacuation_seconds(snapshot)
				_boss_name.text += " · 탈출구 개방까지 %d초" % remaining if remaining > 0 else " · 탈출구 개방"
			else:
				_boss_health.max_value = entity.max_hp
				_boss_health.value = entity.hp
			break
		mode = "play"
		if snapshot.phase in ["won","dead","abandoned"]: mode = snapshot.phase
		elif not snapshot.get("upgrade_offer",{}).is_empty(): mode = "upgrade"
		elif not snapshot.pause_reasons.is_empty(): mode = "pause"
		if snapshot.phase == "evacuation":
			var remaining := _evacuation_seconds(snapshot)
			_hud.text = "주민 대피 %d초" % remaining if remaining > 0 else "대피 완료 · 출구에 도착하면 탈출"
	if not _scenario_page.is_empty(): mode = _scenario_page
	if not _supply_mode.is_empty(): mode = _supply_mode
	if _owned_open: mode = "owned_skills"
	if not _detail_id.is_empty(): mode = "evolution_detail"
	if _settings_open: mode = "settings"
	if not _recovery_view.is_empty(): mode = "save_recovery"
	if mode in ["scenario_select","scenario_briefing","new_run_confirm"]:
		for control in [_hud,_owned_hud,_health,_xp,_boss_health,_boss_name,_objective,get_node("Pause")]: control.hide()
	_stick_base.visible = mode == "play" and _input_kind != "gamepad"
	_stick_knob.visible = _stick_base.visible
	_hint.hide()
	_update_stick()
	var offer_id: String = snapshot.get("upgrade_offer",{}).get("offer_id","")
	_notice.visible = not _notice.text.is_empty()
	var notice_parent: Node = self if mode == "play" else _panel.get_node("Body")
	if _notice.get_parent() != notice_parent:
		_notice.reparent(notice_parent)
		if notice_parent != self: notice_parent.move_child(_notice,2)
	_sync_upgrade_notice(mode)
	_loot_hud.visible = mode in ["play","pause","upgrade"] and not snapshot.is_empty()
	var loot_text := "획득 골드 %d" % int(snapshot.get("loot",{}).get("gold",0)) if Loot.enabled(snapshot) else ""
	if _xp_feedback_seconds > 0.0:
		loot_text += (" · " if not loot_text.is_empty() else "")+"+%d XP" % _xp_feedback_amount
	_loot_hud.text = loot_text
	_reward_feedback.visible = mode == "play"
	_reward_feedback.active = mode == "play"
	if mode == _mode and offer_id == _offer_id: return
	_mode = mode
	_scroll.follow_focus = mode != "evolution_detail"
	_offer_id = offer_id
	_overlay.visible = mode != "play"
	_overlay.color.a = 0.42 if mode == "title" else 0.82
	_clear_choices()
	_focus_index = 0
	_target_button.hide()
	match mode:
		"save_recovery":
			_render_recovery_panel()
		"title":
			_title.text = "진격의 거인 인류의 날개"
			_subtitle.text = "상자와 획득 표시를 개선했습니다. 회복 포션은 새 출격부터 나옵니다."
			if _checkpoint_available: _add_button("이어서 출격",func(): resume_requested.emit())
			_add_button("새로 출격",open_scenario_selection).set_meta("semantic_id","new_run_open")
			_add_button("설정",open_settings)
			if not _supply_view.is_empty():
				_add_button("상점 · 영구 강화",open_supply_shop).set_meta("semantic_id","shop_open")
		"scenario_select":
			_title.text = "시나리오 선택"
			_subtitle.text = ""
			for id in Characters.SCENARIOS:
				var available: bool = Characters.SCENARIOS[id].implementation_status == "implemented"
				var label := "시나리오 1 · "+_chapter_title() if id == Characters.DEFAULT_CHAPTER else "시나리오 2 · 준비 중"
				var button := _add_button(label,open_scenario_briefing.bind(id))
				button.set_meta("semantic_id","scenario:"+id)
				button.disabled = not available
			_add_button("뒤로",close_scenario_page).set_meta("semantic_id","scenario_back")
		"scenario_briefing":
			_title.text = "시나리오 1 · "+_chapter_title()
			_subtitle.text = "845년, 성벽이 무너졌다. 주민이 떠날 때까지 버텨라.\n30분 생존 · 다섯 강적 · 마지막 탈출\n새 출격: 경험치 등급 · 필드/강적 보상함 적용"
			_add_button("출격",_request_new_run).set_meta("semantic_id","scenario_start")
			_add_button("뒤로",close_scenario_page).set_meta("semantic_id","scenario_back")
		"new_run_confirm":
			_title.text = "새로 출격"
			_subtitle.text = "진행 중인 전투를 종료하고 새로 출격할까요?"
			_add_button("종료하고 출격",_confirm_new_run).set_meta("semantic_id","new_run_confirm")
			_add_button("취소",close_scenario_page).set_meta("semantic_id","scenario_back")
		"upgrade":
			_title.text = "전열을 가다듬어라"
			_subtitle.text = _growth_subtitle()
			var offer: Dictionary = _growth_view.get("active_offer",{})
			if str(offer.get("offer_id","")) != offer_id: offer = snapshot.get("upgrade_offer",{})
			_render_growth_cards(offer)
		"owned_skills":
			_render_owned_skills()
		"evolution_detail":
			_render_evolution_detail()
		"shop", "loadout":
			_render_supply_panel()
		"pause":
			_title.text = "잠시 숨을 고르자"
			_subtitle.text = "전투와 생존 시간이 정지했습니다."
			_add_button("계속",func(): resume_requested.emit())
			_add_button("보유 기술 · 레벨과 진화 조건",open_owned_skills).set_meta("semantic_id","owned_open")
			_add_button("설정",open_settings)
			if not _supply_view.is_empty(): _add_button("보급소 · 전투 중 구매 불가",open_supply_shop).set_meta("semantic_id","shop_open")
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
		"won","dead","abandoned":
			_title.text = {"won":"주민 대피 완료","dead":"끝까지 싸웠다","abandoned":"전열에서 퇴각"}[mode]
			_subtitle.text = {"won":"당신이 확보한 시간이 생명을 구했습니다.","dead":"다른 성장 조합으로 다시 도전하세요.","abandoned":"이번 출격을 종료했습니다. 보급소에서 다음 출격을 준비하세요."}[mode]
			_add_button("다시 출격",open_scenario_selection).set_meta("semantic_id","new_run_open")
			if not _supply_view.is_empty(): _add_button("상점 · 영구 강화",open_supply_shop).set_meta("semantic_id","shop_open")
	if _new_run_waiting and not _scenario_page.is_empty():
		for button in _buttons: button.disabled = true
	reflow(_screen_size,_safe_rect)
	if not _buttons.is_empty(): _buttons[_focus_index].grab_focus()
func open_scenario_selection() -> void:
	if _new_run_waiting: return
	_scenario_page = "scenario_select"
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
func open_scenario_briefing(id: String) -> void:
	if _new_run_waiting or id != Characters.DEFAULT_CHAPTER or Characters.SCENARIOS[id].implementation_status != "implemented": return
	_scenario_page = "scenario_briefing"
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
func close_scenario_page() -> void:
	if _new_run_waiting: return
	_scenario_page = {"new_run_confirm":"scenario_briefing","scenario_briefing":"scenario_select"}.get(_scenario_page,"")
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
func _request_new_run() -> void:
	if _new_run_waiting or _scenario_page != "scenario_briefing": return
	if _checkpoint_available:
		_scenario_page = "new_run_confirm"
		_arm_transition_gate()
		_mode = ""
		present(_snapshot)
		return
	_set_new_run_waiting(true)
	new_run_requested.emit()
func _confirm_new_run() -> void:
	if _new_run_waiting or _scenario_page != "new_run_confirm": return
	_set_new_run_waiting(true)
	new_run_replacement_confirmed.emit(_checkpoint_run_id)
func _set_new_run_waiting(waiting: bool) -> void:
	_new_run_waiting = waiting
	_mode = ""
	present(_snapshot)
func finish_new_run_navigation() -> void:
	_scenario_page = ""
	_new_run_waiting = false
	_mode = ""
func present_recovery(view: Dictionary) -> void:
	if _recovery_view == view: return
	var previous_focus := focused_semantic_id()
	_recovery_view = view.duplicate(true)
	_arm_transition_gate()
	_mode = ""
	cancel_touch()
	present(_snapshot)
	_restore_focus(previous_focus)
func _render_recovery_panel() -> void:
	_title.text = "저장 파일 확인"
	var kind: String = str(_recovery_view.get("kind","blocked"))
	var code: String = str(_recovery_view.get("error_code",""))
	if _recovery_view.get("lifecycle_blocked",false):
		_title.text = "잠시 숨을 고르자"
		_subtitle.text = "저장 선택과 전투가 멈췄습니다. 기존 파일은 그대로 보관됩니다."
		if _recovery_view.get("foreground",true):
			_add_button("계속 · 저장 선택으로 돌아가기",func(): recovery_continue_requested.emit()).set_meta("semantic_id","recovery_continue")
		return
	match kind:
		"checkpoint":
			_title.text = "이전 전투를 보관할까요?"
			var offer: Dictionary = _recovery_view.get("offer",{})
			_subtitle.text = "이전 전투는 현재 버전에서 이어갈 수 없습니다 (%s).\n원본과 연결된 월드 저장을 보관한 뒤 같은 진척으로 새 출격합니다. 이전 전투 보상·보급품 환급은 없습니다.\n선택한 장착 보급품은 새 출격에 한 번 소비됩니다. 보급금 %d" % [code,int(offer.get("supply_credits",0))]
			_add_button("기존 전투 보관 · 돌아가기",func(): recovery_keep_requested.emit()).set_meta("semantic_id","recovery_keep")
			_add_button("이전 전투 보관 후 새 출격",func(): recovery_start_requested.emit()).set_meta("semantic_id","recovery_start")
			if not str(offer.get("loadout",{}).get("supply_item_id","")).is_empty():
				var supply: String = str(_recovery_view.get("selection",{}).get("supply_item_id",""))
				_add_button("보급품: " + ("야전 붕대 사용 · 변경" if not supply.is_empty() else "사용 안 함 · 변경"),func(): recovery_supply_toggled.emit()).set_meta("semantic_id","recovery_supply")
			if code == "invalid_loadout": _subtitle.text += "\n보유한 장착 보급품이 부족합니다. 보급품 사용 여부를 선택해주세요."
		"retry":
			_subtitle.text = "저장 파일을 읽지 못했습니다. 자동 재시도하지 않으며 기존 파일을 보관합니다 (%s)." % code
			_add_button("다시 읽기",func(): recovery_retry_requested.emit()).set_meta("semantic_id","recovery_retry")
			_add_button("보관 · 돌아가기",func(): recovery_keep_requested.emit()).set_meta("semantic_id","recovery_keep")
		"initialization_retry":
			_title.text = "저장 준비 결과 확인이 필요합니다"
			_subtitle.text = "기존 파일과 같은 저장 준비 요청을 보관합니다 (%s). 결과를 확인하기 전에는 출격하지 않으며 새 계정을 다시 만들지 않습니다." % code
			_add_button("같은 저장 준비 확인 · 재시도",func(): recovery_retry_requested.emit()).set_meta("semantic_id","recovery_retry")
			_add_button("보관 · 돌아가기",func(): recovery_keep_requested.emit()).set_meta("semantic_id","recovery_keep")
		"recovery_retry", "recovery_pending":
			_title.text = "저장 결과 확인이 필요합니다" if kind == "recovery_pending" else "새 출격을 저장하지 못했습니다"
			_subtitle.text = "기존 전투와 보관 기록을 유지합니다 (%s). 같은 요청의 저장 결과를 확인하고 필요할 때만 다시 시도합니다. 확인 전에는 출격하지 않습니다." % code
			_add_button("같은 요청 확인 · 재시도",func(): recovery_retry_requested.emit()).set_meta("semantic_id","recovery_retry")
		"kept":
			_subtitle.text = "기존 저장을 그대로 보관했습니다. 저장 확인 화면에서 다시 결정할 수 있습니다."
			if _recovery_view.get("has_pending_request",false): _subtitle.text = "기존 저장과 같은 요청을 보관했습니다. 요청 결과를 확인하기 전에는 새 출격이나 다른 요청을 진행하지 않습니다."
			_add_button("같은 요청 확인 · 재시도" if _recovery_view.get("has_pending_request",false) else "저장 확인으로 돌아가기",func(): recovery_retry_requested.emit()).set_meta("semantic_id","recovery_retry")
		"conflict":
			_title.text = "서로 다른 저장이 있습니다"
			_subtitle.text = "기본 저장 폴더와 이전 앱 루트에서 서로 다른 저장을 발견했습니다. 어느 쪽도 선택하거나 합치지 않았습니다. 두 저장을 모두 보관하며 현재 출격을 막습니다."
			for location in _recovery_view.get("locations",[]):
				var summary: Dictionary = location.get("summary",{})
				_subtitle.text += "\n%s: %s · revision %s · 보급금 %s" % ["기본 폴더" if location.location_id == "canonical" else "이전 앱 루트",location.status,str(summary.get("store_revision","?")),str(summary.get("supply_credits","?"))]
			_add_button("두 저장 보관 · 돌아가기",func(): recovery_keep_requested.emit()).set_meta("semantic_id","recovery_keep")
			if _recovery_view.get("has_pending_request",false):
				_add_button("저장 위치 다시 확인 · 같은 요청 유지",func(): recovery_retry_requested.emit()).set_meta("semantic_id","recovery_retry")
		"oversize":
			_title.text = "저장 파일이 너무 큽니다"
			_subtitle.text = "지원 크기 16 MiB를 넘는 저장입니다 (oversize). 파일을 보관하며 자동 재시도하거나 초기화하지 않습니다."
			_add_button("보관 · 돌아가기",func(): recovery_keep_requested.emit()).set_meta("semantic_id","recovery_keep")
			if _recovery_view.get("has_pending_request",false):
				_add_button("크기 상태 다시 확인 · 같은 요청 유지",func(): recovery_retry_requested.emit()).set_meta("semantic_id","recovery_retry")
		_:
			_subtitle.text = "현재 버전에서 안전하게 읽을 수 없는 저장입니다 (%s). 원본을 보관하며 출격이나 초기화를 진행하지 않습니다." % code
			if code == "authority_missing": _subtitle.text = "이전에 확인한 저장 파일을 현재 위치에서 찾을 수 없습니다. 보관 기록과 미확인 요청을 유지하며 새 계정을 생성하지 않습니다. 기존 저장 상태를 확인해주세요."
			_add_button("보관 · 돌아가기",func(): recovery_keep_requested.emit()).set_meta("semantic_id","recovery_keep")
func _add_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.set_meta("semantic_id",text)
	_style_button(button)
	button.pressed.connect(action)
	_choices.add_child(button)
	_register_button(button)
	return button
func _style_button(button: Button) -> void:
	for state_name in ["normal","hover","focus","pressed","disabled"]:
		var art_id := "panel_focus" if state_name in ["hover","focus"] else ("panel_pressed" if state_name == "pressed" else ("panel_disabled" if state_name == "disabled" else "panel_default"))
		var style := _art_style(art_id)
		if style != null: button.add_theme_stylebox_override(state_name,style)
	button.add_theme_color_override("font_color",Color("f0dfba"))
	button.custom_minimum_size = Vector2(0,56)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Let a touch drag beginning on an action reach the existing scroll viewport.
	button.mouse_filter = Control.MOUSE_FILTER_PASS
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
func _register_button(button: Button) -> void:
	_buttons.append(button)
	if not button.has_meta("audio_registered"):
		button.set_meta("audio_registered",true)
		button.pressed.connect(func():
			if not button.disabled:
				var closing := button.text.contains("닫기") or button.text.contains("돌아가기") or button.text.contains("취소")
				audio_requested.emit("cancel" if closing else "select"))
	if not button.has_meta("focus_registered"):
		button.set_meta("focus_registered",true)
		button.focus_entered.connect(func():
			_focus_index = _buttons.find(button)
			if _mode in ["upgrade","loadout"]: call_deferred("_reveal_settled_focus"))
func navigate(action: String) -> void:
	if _mode == "evolution_detail" and action in ["down","up"]:
		_scroll.scroll_vertical = maxi(0,_scroll.scroll_vertical+(96 if action == "down" else -96))
		return
	if action in ["pause","cancel"]:
		if _mode != "save_recovery" or not _recovery_view.get("lifecycle_blocked",false): audio_requested.emit("cancel")
		if _mode == "save_recovery":
			if not _recovery_view.get("lifecycle_blocked",false) and _recovery_view.get("kind") in ["checkpoint","retry","initialization_retry","blocked","conflict","oversize"]: recovery_keep_requested.emit()
			return
		if not _detail_id.is_empty():
			close_evolution_details()
			return
		if _owned_open:
			close_owned_skills()
			return
		if _settings_open:
			close_settings()
			return
		if _mode == "loadout":
			open_supply_shop()
			return
		if _mode == "shop":
			close_supply_shop()
			return
		if not _scenario_page.is_empty():
			close_scenario_page()
			return
		if _mode == "play": pause_changed.emit(true)
		elif _mode == "pause": resume_requested.emit()
		return
	if _buttons.is_empty(): return
	if action in ["down","right","up","left"]:
		var step := 1 if action in ["down","right"] else -1
		for ignored in range(_buttons.size()):
			_focus_index = posmod(_focus_index+step,_buttons.size())
			if _can_focus_button(_buttons[_focus_index]): break
	elif action == "accept":
		if _accept_transition_gate or _buttons[_focus_index].disabled: return
		_dispatching_accept = true
		# Consume the viewport accept too, so focused Buttons cannot also activate.
		if is_inside_tree(): get_viewport().set_input_as_handled()
		_buttons[_focus_index].pressed.emit()
		_dispatching_accept = false
	if not _buttons.is_empty() and _can_focus_button(_buttons[_focus_index]): _buttons[_focus_index].grab_focus()
func _can_focus_button(button: Button) -> bool:
	if not button.disabled: return true
	# Shop cards hold their complete description and refusal reason. Read focus
	# never enables a purchase; both accept and the panel retain disabled guards.
	if not button.is_visible_in_tree(): return false
	var id = button.get_meta("semantic_id","")
	if _mode == "loadout" and _supply_panel is PreparationPanel and id is String and id.begins_with("character:") and id != "character:":
		return _supply_panel.option_button("character_id",id.trim_prefix("character:")) == button
	if _mode != "shop" or not _supply_panel is ShopPanel: return false
	if not id is String or not id.begins_with("purchase:") or id == "purchase:": return false
	return _supply_panel.item_button(id.trim_prefix("purchase:")) == button
func accept_released() -> void:
	_accept_transition_gate = false
func _arm_transition_gate() -> void:
	if _dispatching_accept: _accept_transition_gate = true
func focused_semantic_id() -> String:
	if _buttons.is_empty() or _focus_index >= _buttons.size(): return ""
	return str(_buttons[_focus_index].get_meta("semantic_id",""))
func _restore_focus(id: String) -> void:
	var fallback_start := 0
	for index in range(_buttons.size()):
		if str(_buttons[index].get_meta("semantic_id","")) != id: continue
		if _can_focus_button(_buttons[index]):
			_focus_index = index
			_buttons[index].grab_focus()
			return
		# Keep the existing in-flight loadout identity. Shop read focus above is
		# restricted to visible, valid product cards even while a request is locked.
		if _supply_locked and _supply_mode == "loadout":
			_focus_index = index
			return
		fallback_start = index+1
		break
	for offset in range(_buttons.size()):
		var index := posmod(fallback_start+offset,_buttons.size())
		if _can_focus_button(_buttons[index]):
			_focus_index = index
			_buttons[index].grab_focus()
			return
func _clear_choices() -> void:
	# A recycled slot must never reinterpret a down event from an older offer,
	# modal or authority. Focus-only and supply-only updates never reach here.
	_growth_generation += 1
	for child in _choices.get_children():
		if child is VBoxContainer and child in _growth_groups:
			child.hide()
		else:
			_choices.remove_child(child)
			child.queue_free()
	_buttons.clear()
func reset_obsolete_presentation(snapshot: Dictionary, checkpoint_available: bool, checkpoint_run_id: String = "") -> void:
	_xp_feedback_run = ""
	_xp_feedback_seq = 0
	_xp_feedback_amount = 0
	_xp_feedback_seconds = 0.0
	# Authority replacement invalidates cached run views and their modal return
	# paths. This is presentation-only and must not emit gameplay/shop intents.
	reset_progression_feedback()
	_growth_view = {}
	_owned_open = false
	_detail_origin = "upgrade"
	_owned_hud.present({})
	for index in range(_growth_cards.size()): _clear_growth_slot(index)
	_detail_id = ""
	_return_focus_id = ""
	_supply_view = {}
	_supply_mode = ""
	_supply_panel = null
	_supply_origin_focus = ""
	_modal_focus = {"shop":"","loadout":""}
	_supply_locked = false
	_supply_waiting_result = false
	_supply_lock_revision = -1
	_last_action_result = {}
	_settings_open = false
	finish_new_run_navigation()
	_snapshot = {}
	_mode = ""
	_offer_id = ""
	_checkpoint_available = checkpoint_available
	_checkpoint_run_id = checkpoint_run_id
	_arm_transition_gate()
	cancel_touch()
	set_save_notice("")
	present(snapshot)
func present_progression(view: Dictionary) -> void:
	var reuse_controls := _can_reuse_growth_controls(view)
	var previous_focus := focused_semantic_id()
	var previous_offer_id := _offer_id
	_growth_view = view.duplicate(true)
	_owned_hud.present(view)
	# A pointer press focuses the card before release. Core records that focus
	# in its view revision; rebuilding here would delete the pressed Button.
	if reuse_controls: return
	var offer: Dictionary = _growth_view.get("active_offer",{})
	if offer.is_empty():
		_target_button.hide()
		if _owned_open:
			_mode = ""
			present(_snapshot)
			_restore_focus(previous_focus)
			return
		if _mode in ["upgrade","evolution_detail"]:
			_clear_choices()
			for index in range(_growth_cards.size()): _clear_growth_slot(index)
			_detail_id = ""
			_return_focus_id = ""
			_offer_id = ""
		return
	if not _detail_id.is_empty():
		_mode = ""
		present(_snapshot)
		return
	_mode = "upgrade"
	_hint.hide()
	_scroll.follow_focus = true
	_offer_id = str(offer.get("offer_id",""))
	_overlay.show()
	_clear_choices()
	_title.text = "전열을 가다듬어라"
	_subtitle.text = _growth_subtitle()
	_render_growth_cards(offer)
	reflow(_screen_size,_safe_rect)
	# NEW reconstruction fix: current focus belongs only to the same offer.
	_restore_focus(previous_focus if previous_offer_id == _offer_id and not previous_focus.is_empty() else str(offer.get("selected_option_id","")))
func _can_reuse_growth_controls(view: Dictionary) -> bool:
	if _mode != "upgrade" or not _detail_id.is_empty() or _buttons.is_empty(): return false
	var next_offer: Dictionary = view.get("active_offer",{})
	if next_offer.is_empty() or str(next_offer.get("offer_id","")) != _offer_id: return false
	var previous_content := _growth_view.duplicate(true)
	var next_content := view.duplicate(true)
	# Ignore only the two fields that real Core focus can change. Offer identity,
	# every option/value/availability field, recipes, slots and unknown future
	# content must remain equal; a changed offer still cancels an old press.
	for content in [previous_content,next_content]:
		content.erase("view_revision")
		var offer: Dictionary = content.get("active_offer",{})
		offer.erase("selected_option_id")
	return previous_content == next_content
func _growth_subtitle() -> String:
	var copy := ""
	var slots: Dictionary = _growth_view.get("slots",{})
	if slots.has("equipment") and slots.has("passive"):
		copy = "무기 %d/%d · 보조 %d/%d" % [slots.equipment.used,slots.equipment.max,slots.passive.used,slots.passive.max]
	return copy
func _prepare_growth_controls() -> void:
	for index in range(3):
		var group := VBoxContainer.new()
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.add_theme_constant_override("separation",6)
		group.hide()
		_choices.add_child(group)
		_growth_groups.append(group)
		var card = Card.new()
		_style_button(card)
		group.add_child(card)
		_growth_cards.append(card)
		card.layout_metrics_changed.connect(_queue_growth_layout)
		card.resized.connect(_queue_growth_layout)
		_register_button(card)
		card.button_down.connect(func(): card.set_meta("growth_press_generation",_growth_generation))
		card.chosen.connect(func(_option_id):
			if _consume_growth_press(card): _request_upgrade(str(card.get_meta("semantic_id",""))))
		card.focus_entered.connect(func():
			if _mode == "upgrade" and card.is_visible_in_tree(): upgrade_focus_changed.emit(str(card.get_meta("semantic_id",""))))
		var requirements := VBoxContainer.new()
		requirements.name = "Requirements"
		requirements.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(requirements)
		var details := Button.new()
		_style_button(details)
		details.custom_minimum_size = Vector2(48,48)
		details.size_flags_horizontal = Control.SIZE_SHRINK_END
		details.mouse_filter = Control.MOUSE_FILTER_STOP
		card.add_child(details)
		card.attach_inline_controls(requirements,details)
		_growth_details.append(details)
		_register_button(details)
		details.button_down.connect(func(): details.set_meta("growth_press_generation",_growth_generation))
		details.pressed.connect(func():
			if _consume_growth_press(details): _open_growth_details(str(card.get_meta("semantic_id",""))))
		_clear_growth_slot(index)
func _consume_growth_press(button: Button) -> bool:
	if _mode != "upgrade" or _growth_waiting_result or not button.is_visible_in_tree() or button.disabled: return false
	var valid := _dispatching_accept or int(button.get_meta("growth_press_generation",-1)) == _growth_generation
	button.set_meta("growth_press_generation",-1)
	return valid
func _clear_growth_slot(index: int) -> void:
	_growth_groups[index].hide()
	_growth_cards[index].clear()
	Icons.append_requirements(_growth_cards[index].get_node("Requirements"),[])
	var details := _growth_details[index]
	details.text = ""
	details.tooltip_text = ""
	details.set_meta("semantic_id","")
	details.disabled = true
func _menu_width(safe_width: float) -> float:
	return minf(730 if _mode in ["upgrade","shop","loadout","owned_skills","evolution_detail","save_recovery"] else 520,safe_width-32)
func _menu_columns() -> int:
	# Internal 48px information and full criterion names need usable card width.
	return 2 if _screen_size.x > _screen_size.y and _safe_rect.size.x >= 760 and _mode == "upgrade" else 1
func _prepare_growth_widths(option_count: int) -> void:
	# Hidden slots do not participate in native container sorting. Give their
	# existing EXPAND_FILL controls usable horizontal space before binding text.
	# Native layout still owns heights, pixel remainder and AUTO scrollbar changes.
	var count := mini(option_count,_growth_groups.size())
	if count == 0: return
	var width := _menu_width(_safe_rect.size.x)-_panel.get_theme_stylebox("panel").get_minimum_size().x
	var scroll_style := _scroll.get_theme_stylebox("panel")
	for side in [SIDE_LEFT,SIDE_RIGHT]:
		var margin := scroll_style.get_margin(side)
		if _scroll.draw_focus_border:
			margin = maxf(margin,_scroll.get_theme_stylebox("focus").get_margin(side))
		width -= margin
	var scrollbar := _scroll.get_v_scroll_bar()
	if scrollbar.visible and scrollbar.get_parent() == _scroll:
		width -= scrollbar.get_combined_minimum_size().x+_scroll.get_theme_constant("scrollbar_h_separation")
	var columns := _menu_columns()
	width -= _choices.get_theme_constant("h_separation")*maxi(mini(count,columns)-1,0)
	var column_width := maxf(0,ceilf(width/columns))
	for index in range(count):
		_growth_groups[index].size.x = column_width
		_growth_cards[index].size.x = _growth_groups[index].size.x
		_growth_details[index].size.x = 48
func _render_growth_cards(offer: Dictionary) -> void:
	var options: Array = offer.get("options",[])
	_prepare_growth_widths(options.size())
	for index in range(_growth_groups.size()):
		if index >= options.size():
			_clear_growth_slot(index)
			continue
		var option: Dictionary = options[index]
		var card = _growth_cards[index]
		card.present(option,_growth_summary(option))
		Card.append_evolution_requirements(card.get_node("Requirements"),option)
		# Keep Card's complete display/tooltip available, but make the selectable
		# face small enough that focus scrolling cannot hide its name or action.
		_register_button(card)
		var id := str(option.get("option_id",""))
		if id == offer.get("selected_option_id",""): _focus_index = _buttons.size()-1
		var details := _growth_details[index]
		details.text = "i"
		details.tooltip_text = str(option.get("name","성장"))+" · 효과와 조건"
		details.set_meta("semantic_id","growth_detail:"+id)
		details.disabled = false
		_register_button(details)
		card.sync_inline_layout()
		_growth_groups[index].show()
	# Information is available from each independent i target and the owned
	# reader. Do not repeat another full-width reading action above the choices.
	_target_button.hide()
	_queue_growth_layout()
func _queue_growth_layout() -> void:
	if _growth_layout_queued or not is_inside_tree(): return
	_growth_layout_queued = true
	call_deferred("_sync_growth_layout")
func _sync_growth_layout() -> void:
	_growth_layout_queued = false
	var metrics := Vector3.ZERO
	for index in range(_growth_cards.size()):
		if not _growth_groups[index].visible: continue
		var own: Vector3 = _growth_cards[index].layout_metrics()
		metrics = Vector3(maxf(metrics.x,own.x),maxf(metrics.y,own.y),maxf(metrics.z,own.z))
	for index in range(_growth_cards.size()):
		if _growth_groups[index].visible: _growth_cards[index].apply_shared_layout(metrics)
func _growth_summary(option: Dictionary) -> String:
	return Card.summary(option)
func _open_growth_details(option_id: String) -> void:
	# Reuse the read-only detail modal lifecycle and its B/accept-release gate.
	open_evolution_details("option:"+option_id)
func _evolution_name(detail: Dictionary) -> String:
	return str(detail.get("name",detail.get("evolution_id","진화")))
func open_evolution_details(evolution_id: String = "") -> void:
	if _growth_view.is_empty(): return
	_detail_origin = "owned_skills" if _owned_open else "upgrade"
	_return_focus_id = focused_semantic_id()
	_detail_id = evolution_id if not evolution_id.is_empty() else str(_growth_view.get("target",{}).get("evolution_id",""))
	if _detail_id.is_empty(): return
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
func close_evolution_details() -> void:
	_detail_id = ""
	_arm_transition_gate()
	if _detail_origin == "owned_skills":
		_mode = ""
		present(_snapshot)
	else:
		present_progression(_growth_view)
	_restore_focus(_return_focus_id)
func _render_evolution_detail() -> void:
	_title.text = "진화 레시피"
	_subtitle.text = "위/아래로 읽기 · B 뒤로\n성장 선택은 유지됩니다"
	_scroll.follow_focus = false
	_scroll.scroll_vertical = 0
	if _detail_id.begins_with("owned:"):
		_title.text = "보유 기술 효과와 진화"
		_subtitle.text = "위/아래로 읽기 · B 보유 기술로 돌아가기\n전투와 생존 시간은 정지되어 있습니다"
		var row := _owned_row(_detail_id.trim_prefix("owned:"))
		var recipe := _owned_recipe(row)
		var panel = DetailPanel.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.present_owned(row,recipe)
		_choices.add_child(panel)
	elif _detail_id.begins_with("option:"):
		_title.text = "성장 효과와 조건"
		for option in _growth_view.get("active_offer",{}).get("options",[]):
			if str(option.get("option_id","")) != _detail_id.trim_prefix("option:"): continue
			var full_card = Card.new()
			full_card.present(option)
			var content := Label.new()
			content.name = "GrowthDetails"
			content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			content.add_theme_color_override("font_color",Color("f0dfba"))
			# The recipe is read-only: avoid presenting its copied A prompt as an
			# actionable choice while in the detail modal.
			content.text = full_card.display_text().trim_suffix("\n\nA · 선택")
			full_card.free()
			_choices.add_child(content)
			var requirements := VBoxContainer.new()
			requirements.name = "Requirements"
			Card.append_evolution_requirements(requirements,option)
			_choices.add_child(requirements)
			break
	else:
		var detail: Dictionary = {}
		for evolution in _growth_view.get("evolutions",[]):
			if str(evolution.get("evolution_id","")) == _detail_id: detail = evolution
		var panel = DetailPanel.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.present(detail)
		_choices.add_child(panel)
	_add_button("보유 기술로 돌아가기" if _detail_origin == "owned_skills" else "성장 선택으로 돌아가기",close_evolution_details).set_meta("semantic_id","detail_back")
func open_owned_skills() -> void:
	if _mode not in ["play","pause"] or _growth_view.get("owned",{}).is_empty(): return
	# The existing synchronous controller path must establish real Core pause.
	# A UI overlay alone is not evidence that combat has stopped.
	if _mode == "play": pause_changed.emit(true)
	if _snapshot.get("pause_reasons",[]).is_empty(): return
	_owned_open = true
	_detail_id = ""
	_arm_transition_gate()
	_mode = ""
	cancel_touch()
	present(_snapshot)
func close_owned_skills() -> void:
	_owned_open = false
	_detail_id = ""
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
	_restore_focus("owned_open")
func _render_owned_skills() -> void:
	_title.text = "보유 기술"
	_subtitle.text = "현재 출격의 기술 · A 효과와 진화 조건\nB 일시정지로 돌아가기"
	for kind in ["equipment","passives"]:
		var rows: Array = _growth_view.get("owned",{}).get(kind,[])
		for index in 4:
			if index < rows.size():
				var row: Dictionary = rows[index]
				var id := str(row.get("item_id",""))
				var title := str(row.get("name",""))
				if row.get("is_evolved",false): title = OwnedHUD.evolution_name(_growth_view,str(row.get("evolution_id","")))
				var button := _add_button(title+" · "+OwnedHUD.level_text(row),func(): open_evolution_details("owned:"+id))
				button.set_meta("semantic_id","owned:"+id)
				button.icon = Icons.texture_for(Icons.icon_id_for(row))
				button.add_theme_constant_override("icon_max_width",32)
			else:
				var empty := Label.new()
				empty.text = ("장비" if kind == "equipment" else "보조")+" · 빈 칸"
				_choices.add_child(empty)
	if _snapshot.get("character_id","") == "mikasa_01":
		var signature := Label.new()
		signature.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		signature.text = "집중 연격 · 가까운 적 한 명에게 자동 3연격\n18 / 18 / 36 피해 · 0 / 0.13 / 0.27초 · 재사용 12초\n매 타격 범위·방향·엄폐를 다시 확인합니다. 고유 슬롯이며 장비 칸을 사용하지 않습니다.\n초기 수치 · 글로벌 피해 강화 적용 · 대표 궁극 미구현" if Signature.enabled(_snapshot) else "고유 공격 · 다음 미카사 출격부터 집중 연격을 사용합니다."
		_choices.add_child(signature)
	_add_button("일시정지로 돌아가기",close_owned_skills).set_meta("semantic_id","owned_back")
func _owned_row(id: String) -> Dictionary:
	for kind in ["equipment","passives"]:
		for row in _growth_view.get("owned",{}).get(kind,[]):
			if row.get("item_id","") == id: return row
	return {}
func _owned_recipe(row: Dictionary) -> Dictionary:
	for recipe in _growth_view.get("evolutions",[]):
		if recipe.get("evolution_id","") == row.get("evolution_id",""): return recipe
	return {}
func _request_upgrade(option_id: String) -> void:
	if _growth_waiting_result: return
	_arm_transition_gate()
	upgrade_chosen.emit(_offer_id,option_id)
func set_upgrade_pending(enabled: bool) -> void:
	if _growth_waiting_result == enabled: return
	_growth_waiting_result = enabled
	for index in _growth_cards.size():
		if not _growth_groups[index].visible: continue
		var option: Dictionary = _growth_cards[index]._option
		_growth_cards[index].disabled = enabled or not bool(option.get("can_select",true)) or option.get("status","") == "evolved"
		_growth_details[index].disabled = enabled
func confirmed_upgrade_text() -> String:
	return _growth_notice_text
func reset_progression_feedback() -> void:
	_growth_waiting_result = false
	_growth_notice_text = ""
	_growth_notice_seconds = 0.0
	if is_instance_valid(_growth_notice): _growth_notice.hide()
	set_process(false)
func present_confirmed_upgrades(events: Array, view: Dictionary) -> void:
	# Called only after Controller has adopted a read-back confirmed save.
	# Old offered levels are presentation context; new values come from this DTO.
	var previous_offer: Dictionary = _growth_view.get("active_offer",{}).duplicate(true)
	present_progression(view)
	for event in events:
		if event.get("type","") != "upgrade_applied": continue
		var payload: Dictionary = event.get("payload",{})
		var kind := str(payload.get("kind",""))
		var row := _owned_row(str(payload.get("item_id","")))
		if kind == "evolution":
			for owned in view.get("owned",{}).get("equipment",[]):
				if owned.get("evolution_id","") == payload.get("item_id",""): row = owned
		if row.is_empty(): continue
		var option := {}
		if previous_offer.get("offer_id","") == payload.get("offer_id",""):
			for offered in previous_offer.get("options",[]):
				if offered.get("option_id","") == payload.get("option_id",""): option = offered
		var title := str(row.get("name",""))
		var detail := str(row.get("attack_summary",""))
		if kind == "evolution" and row.get("is_evolved",false):
			title = OwnedHUD.evolution_name(view,str(row.evolution_id))+" · "+OwnedHUD.level_text(row)
			_growth_notice_seconds = 2.0
		else:
			var level := OwnedHUD.level_text(row)
			if not row.get("is_max",false) and option.has("level"):
				level = ("신규 습득 · Lv %d/%d" % [int(row.level),int(row.max_level)]) if int(option.level) == 0 else ("Lv %d → %d/%d" % [int(option.level),int(row.level),int(row.max_level)])
			title += " · "+level
			var effect := Card.effect_text(option.get("effect_delta",{}))
			if not effect.is_empty(): detail = effect.split("\n")[0]
			if row.get("is_max",false):
				for condition in row.get("requirements",[]):
					if not condition.get("met",false):
						detail = Card.requirements_text([condition])
						break
			_growth_notice_seconds = 1.4
		_reward_feedback.confirmed_skill(str(row.get("name",""))+" %d/%d" % [int(row.get("level",0)),int(row.get("max_level",5))],_art_texture(_item_icon(str(row.get("item_id","")))))
		_growth_notice_text = title+"\n"+detail
		_owned_hud.highlight(str(row.get("item_id","")))
		_sync_upgrade_notice(_mode)
		set_process(true)
func _sync_upgrade_notice(mode: String) -> void:
	var parent: Node = _panel.get_node("Body") if mode == "upgrade" else self
	if _growth_notice.get_parent() != parent:
		_growth_notice.reparent(parent)
		if parent != self: parent.move_child(_growth_notice,2)
		else:
			_growth_notice.position = Vector2(_safe_rect.position)+Vector2(8,(226 if _screen_size.y > _screen_size.x else 148)+(24 if _owned_hud.signature_visible() else 0))
			_growth_notice.size = Vector2(_safe_rect.size.x-16,44)
	var compact_notice := mode == "upgrade" and _screen_size.x > _screen_size.y and _safe_rect.size.y < 400
	var notice := _growth_notice_text.split("\n")[0] if compact_notice else _growth_notice_text
	var text := ("직전 선택 · " if mode == "upgrade" else "")+notice
	_growth_notice.tooltip_text = _growth_notice_text
	if _growth_notice.text != text: _growth_notice.text = text
	_growth_notice.visible = not _growth_notice_text.is_empty() and mode in ["play","upgrade"]
func consume_loot_events(events: Array, run_id: String) -> void:
	_reward_feedback.consume(events,run_id)
	if _xp_feedback_run != run_id:
		_xp_feedback_run = run_id
		_xp_feedback_seq = 0
		_xp_feedback_amount = 0
		_xp_feedback_seconds = 0.0
	var gained := 0
	for event in events:
		if event.get("type","") != "xp_gained": continue
		var prefix := run_id+":"
		var id: String = event.get("event_id","")
		if not id.begins_with(prefix): continue
		var serial: int = id.trim_prefix(prefix).to_int()
		if serial <= _xp_feedback_seq: continue
		_xp_feedback_seq = serial
		gained += int(event.get("payload",{}).get("amount",0))
	if gained <= 0: return
	_xp_feedback_amount = mini(2147483647,(_xp_feedback_amount if _xp_feedback_seconds > 0.0 else 0)+gained)
	_xp_feedback_seconds = 0.7
	set_process(true)
func _process(delta: float) -> void:
	if _mode != "play": return
	_xp_feedback_seconds = maxf(0.0,_xp_feedback_seconds-delta)
	_growth_notice_seconds = maxf(0,_growth_notice_seconds-delta)
	if _growth_notice_seconds == 0 and not _growth_notice_text.is_empty(): reset_progression_feedback()
	set_process(_xp_feedback_seconds > 0.0 or _growth_notice_seconds > 0.0)
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
func set_checkpoint_available(available: bool, run_id: String = "") -> void:
	if _checkpoint_available == available and _checkpoint_run_id == run_id: return
	_checkpoint_available = available
	_checkpoint_run_id = run_id
	_mode = ""
	present(_snapshot)
func set_save_notice(message: String) -> void:
	if is_instance_valid(_notice):
		_notice.text = message
		_notice.visible = not message.is_empty()
func set_input_hint(kind: String) -> void:
	_input_kind = kind
	_hint.text = ""
	_hint.hide()
func _input(event: InputEvent) -> void:
	# Release observation belongs to the modal UI; the router still emits intents.
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A and not event.pressed: accept_released()
	elif event is InputEventKey and event.keycode in [KEY_ENTER,KEY_SPACE] and not event.pressed: accept_released()
	if _mode != "play": return
	# Godot also sends mouse events for the first touch; only its touch owns the stick.
	if event is InputEventMouse and event.device == -1: return
	if event is InputEventScreenTouch:
		if event.pressed and _touch_id == -1 and event.position.x < size.x*0.55 and event.position.y > size.y*0.4:
			_touch_id = event.index
			_touch_origin = event.position
			_update_stick()
		elif not event.pressed and event.index == _touch_id: cancel_touch()
	elif event is InputEventScreenDrag and event.index == _touch_id:
		_set_touch_vector((event.position-_touch_origin)/TOUCH_RADIUS)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and _touch_id == -1 and event.position.x < size.x*0.55 and event.position.y > size.y*0.4:
			_touch_id = MOUSE_POINTER_ID
			_touch_origin = event.position
			_update_stick()
		elif not event.pressed and _touch_id == MOUSE_POINTER_ID: cancel_touch()
	elif event is InputEventMouseMotion and _touch_id == MOUSE_POINTER_ID:
		_set_touch_vector((event.position-_touch_origin)/TOUCH_RADIUS)
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
	return {"blade_slash":"icon_twin_blades","spin_slash":"icon_spin_slash","odm_dash":"icon_omni_dash","reentry_combo":"icon_reentry_combo","wall_cannon":"icon_wall_cannon","ally_cover":"icon_ally_cover","damage":"icon_damage","fire_interval":"icon_cooldown","movement":"icon_movement","max_health":"icon_health","recovery":"icon_regeneration","pickup":"icon_pickup","pickup_radius":"icon_pickup","range":"icon_range","attack_range":"icon_range","evo_wing_cut":"icon_evo_wing_cut","evo_crossfire":"icon_evo_crossfire","armor":"icon_armor"}.get(id,"")

func _queue_settle_panel(generation: int) -> void:
	# NEW reconstruction repair: schedule one object-bound callback, not a
	# coroutine that can resume after this scene has been destroyed.
	if not is_inside_tree() or is_queued_for_deletion() or generation != _layout_generation: return
	var callback := Callable(self,"_settle_panel")
	if not get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.connect(callback,CONNECT_ONE_SHOT | CONNECT_DEFERRED)
func _settle_panel() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not is_instance_valid(_panel): return
	var safe := Rect2(Vector2(_safe_rect.position),Vector2(_safe_rect.size))
	var width := _menu_width(safe.size.x)
	var desired_height := 490 if _mode == "settings" else ((650 if _screen_size.y > _screen_size.x else 410) if _mode in ["upgrade","shop","loadout","owned_skills","evolution_detail","save_recovery"] else (430 if _mode in ["title","pause","scenario_select","scenario_briefing","new_run_confirm"] else 310))
	# After width propagation, wrapped text has its real minimum height.
	var short_supply := _mode in ["shop","loadout"] and _screen_size.x > _screen_size.y and safe.size.y < 360
	_panel.size = Vector2(width,minf(desired_height,safe.size.y-(12 if short_supply else (32 if _mode == "shop" else 36))))
	_panel.position = safe.position + (safe.size-_panel.size)*0.5
	# Reflow does not change focus, so follow_focus alone misses rotated menus.
	var callback := Callable(self,"_reveal_settled_focus")
	if not get_tree().process_frame.is_connected(callback):
		get_tree().process_frame.connect(callback,CONNECT_ONE_SHOT | CONNECT_DEFERRED)

func _reveal_settled_focus() -> void:
	if not is_inside_tree() or is_queued_for_deletion() or not _scroll.follow_focus: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not _scroll.is_ancestor_of(focused): return
	_scroll.ensure_control_visible(focused)
	if _mode == "upgrade":
		var card: Control = focused if focused in _growth_cards else focused.get_parent() as Control
		if card in _growth_cards: _scroll.ensure_control_visible(card)
		return
	if _mode != "loadout" or not is_instance_valid(_supply_panel): return
	var semantic := str(focused.get_meta("semantic_id",""))
	if not semantic.begins_with("loadout:target_evolution_id:"): return
	var rows := _supply_panel.get_node_or_null("Requirements_"+semantic.trim_prefix("loadout:target_evolution_id:")) as Control
	if rows != null and rows.is_visible_in_tree(): _scroll.ensure_control_visible(rows)

func _set_touch_vector(value: Vector2) -> void:
	var magnitude := value.length()
	_touch_vector = Vector2.ZERO if magnitude <= TOUCH_DEADZONE else value.normalized()*clampf((magnitude-TOUCH_DEADZONE)/(1.0-TOUCH_DEADZONE),0.0,1.0)
	touch_move_changed.emit(_touch_vector)
	_update_stick()
func _update_stick() -> void:
	if not is_instance_valid(_stick_base): return
	var origin := _touch_origin if _touch_id != -1 else Vector2(_safe_rect.position)+Vector2(82,_safe_rect.size.y-94)
	_stick_base.position = origin-Vector2(48,48)
	_stick_knob.position = origin+_touch_vector*TOUCH_RADIUS-Vector2(20,20)
func _bar_colors(bar: ProgressBar, color: Color) -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("20272b")
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background",background)
	bar.add_theme_stylebox_override("fill",fill)

func objective_text(snapshot: Dictionary) -> String:
	if snapshot.is_empty() or snapshot.get("phase","") in ["won","dead","abandoned"]: return ""
	var player: Array = snapshot.player.position if snapshot.player.has("position") else [0,0]
	if snapshot.phase == "evacuation":
		var world: Dictionary = snapshot.get("world",{})
		if world.get("mode","") == "streamed_city" and world.get("stage","") == "city":
			return _city_evacuation_text(world,Vector2(player[0],player[1]))
		var zone: Array = world.get("escape_rect",snapshot.escape_zone) if world.get("stage","") == "dock" else snapshot.escape_zone
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
func _evacuation_seconds(snapshot: Dictionary) -> int:
	return maxi(0,75-int((int(snapshot.active_tick)-int(snapshot.final_started_tick))/60))

func _city_evacuation_text(world: Dictionary, player: Vector2) -> String:
	var preparing := "탈출 통로 준비 중"
	var passage: Dictionary = world.get("evacuation",{})
	if not passage.get("chunk") is Array: return preparing
	var target := Address.parse(passage.chunk)
	if not target.ok or passage.get("passage_id","") != "passage:city_v1:%s:%s" % passage.chunk: return preparing
	# Normalize only the bounded local player position. Absolute chunk strings
	# stay exact signed integers, including adjacent addresses beyond 2^53.
	var location := Address.normalize(world.get("origin_chunk",[]),player)
	if not location.ok: return preparing
	var relative := Address.relative(passage.chunk,Vector2(384,384),location.chunk)
	if relative.ok:
		var offset: Vector2 = relative.local-location.local
		return "탈출 통로 " + _direction_label(offset) + (" · 도착" if offset.length() < 40 else " · %d" % ceili(offset.length()/10))
	# Never subtract distant signed endpoints or cast absolute chunks to float.
	# Outside the working set, show only an explicitly coarse direction, no range.
	var current := Address.parse(location.chunk)
	var dx := signf(384-location.local.x) if target.x == current.x else (1.0 if target.x > current.x else -1.0)
	var dy := signf(384-location.local.y) if target.y == current.y else (1.0 if target.y > current.y else -1.0)
	return "탈출 통로 · 대략 " + _direction_label(Vector2(dx,dy)*16)

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

func _chapter_title() -> String:
	var chapter = JSON.parse_string(FileAccess.get_file_as_string("res://chapters/chapter_01/manifest.json"))
	return str(chapter.get("display_name","시간시나구 탈출")) if chapter is Dictionary else "시간시나구 탈출"

func present_supply(view: Dictionary) -> void:
	var focus := focused_semantic_id()
	_supply_view = view.duplicate(true)
	if _supply_locked and not _supply_waiting_result and int(view.get("view_revision",-1)) != _supply_lock_revision:
		_supply_locked = false
		_last_action_result = {}
	# Supply-only ACKs have no visible supply controls in combat/growth views.
	# Preserve held movement, choice/back presses, focus and detail scrolling.
	if _mode in ["play","upgrade","owned_skills","evolution_detail"]: return
	_mode = ""
	present(_snapshot)
	_restore_focus(focus)
func open_supply_shop() -> void:
	if _supply_view.is_empty():
		shop_open_requested.emit()
		return
	if _supply_mode.is_empty(): _supply_origin_focus = focused_semantic_id()
	else: _modal_focus[_supply_mode] = focused_semantic_id()
	_supply_mode = "shop"
	_detail_id = ""
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
	shop_open_requested.emit()
func open_loadout() -> void:
	if _supply_view.is_empty(): return
	if not _supply_mode.is_empty(): _modal_focus[_supply_mode] = focused_semantic_id()
	_supply_mode = "loadout"
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
func close_supply_shop() -> void:
	if not _supply_mode.is_empty(): _modal_focus[_supply_mode] = focused_semantic_id()
	_supply_mode = ""
	_arm_transition_gate()
	_mode = ""
	present(_snapshot)
	_restore_focus(_supply_origin_focus)
	shop_closed.emit()
func _render_supply_panel() -> void:
	_title.text = "상점 · 영구 강화" if _mode == "shop" else "출격 준비"
	_subtitle.text = "전투 종료 정산 금화
A 확인 · B 뒤로" if _mode == "shop" else "시나리오 1 · %s · 845
A 장착 · B 보급소" % _chapter_title()
	if _mode == "shop":
		var shop = ShopPanel.new()
		shop.present(_supply_view)
		shop.purchase_requested.connect(_request_purchase)
		_supply_panel = shop
	else:
		var preparation = PreparationPanel.new()
		preparation.present(_supply_view)
		preparation.loadout_changed.connect(_request_loadout)
		preparation.character_selected.connect(_request_character_selection)
		preparation.run_start_requested.connect(_request_run_start)
		_supply_panel = preparation
	if _supply_locked:
		_supply_panel.present_action_result(_last_action_result if not _last_action_result.is_empty() else {"ok":false,"message":"저장 처리 중…"})
	_choices.add_child(_supply_panel)
	for button in _supply_panel.action_buttons():
		_style_button(button)
		button.icon = Icons.texture_for(str(button.get_meta("skill_icon_id",""))) if button.has_meta("skill_icon_id") else _art_texture(str(button.get_meta("art_id","")))
		button.add_theme_constant_override("icon_max_width",32)
		_register_button(button)
	if _mode == "shop": _add_button("출격 준비",open_loadout).set_meta("semantic_id","loadout_open")
	_add_button("뒤로",close_supply_shop if _mode == "shop" else open_supply_shop).set_meta("semantic_id","supply_back")
	_restore_focus(str(_modal_focus.get(_mode,"")))
func _lock_supply_request() -> void:
	_supply_locked = true
	_supply_waiting_result = true
	_supply_lock_revision = int(_supply_view.get("view_revision",0))
	_last_action_result = {}
func _request_purchase(id: String, revision: int) -> void:
	if _supply_locked: return
	_lock_supply_request()
	purchase_requested.emit(id,revision)
func _request_loadout(selection: Dictionary, revision: int) -> void:
	if _supply_locked: return
	_lock_supply_request()
	loadout_changed.emit(selection.duplicate(true),revision)
func _request_character_selection(id: String, revision: int) -> void:
	if _supply_locked: return
	_arm_transition_gate()
	_lock_supply_request()
	character_selected.emit(id,revision)
func _request_run_start() -> void:
	if _supply_locked: return
	_lock_supply_request()
	run_start_requested.emit()
func present_action_result(result: Dictionary) -> void:
	var action := str(result.get("action",""))
	if _new_run_waiting and action in ["new_run","run_start","settlement"]:
		if not result.get("ok",false) and result.get("error_code","") != "commit_outcome_unknown":
			_scenario_page = "scenario_briefing"
			_set_new_run_waiting(false)
	if str(result.get("action","")) == "upgrade":
		set_upgrade_pending(false)
		if result.get("ok",false): set_save_notice("")
	if _supply_waiting_result or str(result.get("action","")) in ["purchase","loadout","character_selection","run_start"]:
		_supply_locked = true
		_supply_waiting_result = false
		_supply_lock_revision = int(_supply_view.get("view_revision",0))
		_last_action_result = result.duplicate(true)
		if _supply_mode in ["shop","loadout"] and is_instance_valid(_supply_panel):
			_supply_panel.present_action_result(result.duplicate(true))
	var receipt: Dictionary = result.get("receipt",{})
	if not receipt.is_empty():
		var lines: Array[String] = []
		for key in receipt.get("breakdown",{}):
			lines.append("%s %s" % [str({"kills":"처치","survival":"생존","elites":"강적","minibosses":"강적","clear":"탈출","loot":"보상함"}.get(key,key)),str(receipt.breakdown[key])])
		if receipt.has("total"): lines.append("획득 보급금 %s" % str(receipt.total))
		if not lines.is_empty(): set_save_notice(" · ".join(lines))
	elif not str(result.get("message","")).is_empty(): set_save_notice(str(result.message))
