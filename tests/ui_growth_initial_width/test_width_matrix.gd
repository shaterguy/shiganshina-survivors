extends RefCounted
# Catches stale viewport/style/column width at first bind or after reflow, and
# accidental content, input-generation, focus, scrollbar or sizing changes.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
var enforce_seed := true # Test harness can collect the original semantic oracle.
var observations: Array = []
var signals: Array = []
func _settle(t) -> void:
	for ignored in range(8): await t.process_frame
func _font(control: Control, ui) -> Dictionary:
	var font := control.get_theme_font("font")
	return {"class":font.get_class(),"face":font.get_font_name(),"style":font.get_font_style_name(),"path":font.resource_path,"size":control.get_theme_font_size("font_size"),"same_root":font==ui.get_theme_font("font"),"same_card":font==ui._growth_cards[0].get_theme_font("font")}
func _controls(node: Node, ui, output: Array) -> void:
	if node is Control:
		var item := {"path":str(ui.get_path_to(node)),"class":node.get_class(),"rect":node.get_global_rect(),"visible":node.is_visible_in_tree(),"minimum":node.custom_minimum_size,"hflags":node.size_flags_horizontal,"vflags":node.size_flags_vertical}
		if node is Label or node is Button:
			item.text = node.text
			item.font = _font(node,ui)
			item.autowrap = node.autowrap_mode
		if node is Button:
			item.id = node.get_meta("semantic_id","")
			item.disabled = node.disabled
			item.tooltip = node.tooltip_text
			item.styles = {}
			for key in ["normal","hover","focus","pressed","disabled"]:
				var style: StyleBox = node.get_theme_stylebox(key)
				item.styles[key] = {"class":style.get_class(),"texture":style.texture.resource_path if style is StyleBoxTexture else "","margins":[style.get_margin(SIDE_LEFT),style.get_margin(SIDE_TOP),style.get_margin(SIDE_RIGHT),style.get_margin(SIDE_BOTTOM)]}
		output.append(item)
	for child in node.get_children(): _controls(child,ui,output)
func _capture(ui,label: String) -> void:
	var nodes: Array = []
	_controls(ui,ui,nodes)
	var vertical: VScrollBar = ui._scroll.get_v_scroll_bar()
	observations.append({"label":label,"controls":nodes,"view":ui._growth_view.duplicate(true),"snapshot":ui._snapshot.duplicate(true),"focus":ui.focused_semantic_id(),"mode":ui._mode,"offer":ui._offer_id,"generation":ui._growth_generation,"layout_generation":ui._layout_generation,"detail":ui._detail_id,"return_focus":ui._return_focus_id,"touch_id":ui._touch_id,"touch_vector":ui._touch_vector,"scroll":{"min":vertical.min_value,"max":vertical.max_value,"page":vertical.page,"visible":vertical.visible,"value":ui._scroll.scroll_vertical,"hmode":ui._scroll.horizontal_scroll_mode,"vmode":ui._scroll.vertical_scroll_mode},"signals":signals.duplicate(true)})
func _connect_signals(ui) -> void:
	for definition in ui.get_script().get_script_signal_list():
		var signal_name := str(definition.name)
		match definition.args.size():
			0: ui.connect(signal_name,func():signals.append([signal_name]))
			1: ui.connect(signal_name,func(value):signals.append([signal_name,value]))
			2: ui.connect(signal_name,func(a,b):signals.append([signal_name,a,b]))
func _offer(ui,t,view: Dictionary,snapshot: Dictionary,label: String,first := false) -> void:
	var before_view := view.duplicate(true)
	var before_snapshot := snapshot.duplicate(true)
	var shows: Array = []
	var callbacks: Array = []
	if first:
		for card in ui._growth_cards:
			var observe := func():
				if card.is_visible_in_tree() and not card.face_text().is_empty(): shows.append({"width":card.size.x,"style_min":card.get_theme_stylebox("normal").get_minimum_size().x})
			card.visibility_changed.connect(observe)
			callbacks.append([card,observe])
	# Presentation-only content arrangements retain a matching snapshot offer ID.
	var presented_snapshot := snapshot.duplicate(true)
	presented_snapshot.upgrade_offer.offer_id = view.active_offer.offer_id
	ui.present_progression(view)
	ui.present(presented_snapshot)
	await _settle(t)
	for connection in callbacks: connection[0].visibility_changed.disconnect(connection[1])
	t.check(before_view==view and before_snapshot==snapshot,label+": read-only Core DTOs remain unchanged")
	t.check(ui._scroll.vertical_scroll_mode==ScrollContainer.SCROLL_MODE_AUTO,label+": native AUTO scrollbar mode preserved")
	if first:
		t.check(shows.size()==mini(view.active_offer.options.size(),3),label+": each populated card is observed on first show")
		if enforce_seed:
			for slot in range(shows.size()):
				if ui._growth_cards[slot].size.x>shows[slot].style_min:
					t.check(shows[slot].width>shows[slot].style_min,label+": pre-show width is larger than style minimum")
					# AUTO may add OR remove a scrollbar that belonged to the previous menu.
					var scrollbar_refinement: float = ui._scroll.get_v_scroll_bar().get_combined_minimum_size().x+ui._scroll.get_theme_constant("scrollbar_h_separation")
					t.check(absf(shows[slot].width-ui._growth_cards[slot].size.x)<=scrollbar_refinement+1,label+": native refinement is bounded by scrollbar allocation and pixel remainder")
	_capture(ui,label)
func run(t) -> void:
	var sim = Fixture.simulation(t)
	var state: Dictionary = Fixture.earn_offer(sim,21,24)
	var first: Dictionary = View.new().build(state)
	var snapshot: Dictionary = sim.snapshot(state)
	var chosen: Dictionary = sim.choose_upgrade(state,first.active_offer.offer_id,first.active_offer.options[0].option_id)
	t.check(chosen.get("ok",false),"matrix uses a real Core choice before its next offer")
	if state.upgrade_offer.is_empty(): Fixture.drop_xp(sim,state,40,"width_matrix_next")
	var next: Dictionary = View.new().build(state)
	t.check(next.active_offer.offer_id!=first.active_offer.offer_id and next.active_offer.options!=first.active_offer.options,"matrix next offer has genuinely different Core identity and content")
	var targets := [
		["square",Vector2i(450,450),Rect2i(0,0,450,450)],
		["landscape",Vector2i(800,450),Rect2i(0,0,800,450)],
		["portrait",Vector2i(450,800),Rect2i(0,0,450,800)],
		["small_safe",Vector2i(568,320),Rect2i(16,12,536,296)],
		["narrow_safe",Vector2i(280,450),Rect2i(7,13,266,420)],
		["nondivisible",Vector2i(773,449),Rect2i(19,7,719,428)],
		["portrait_safe",Vector2i(500,900),Rect2i(27,61,446,793)]
	]
	for target in targets:
		var vp := SubViewport.new()
		vp.size = Vector2i(800,450)
		t.root.add_child(vp)
		var ui = UI.new()
		vp.add_child(ui)
		await _settle(t)
		# Change viewport/safe area immediately before the first real bind.
		vp.size = target[1]
		ui.reflow(target[1],target[2])
		signals = []
		_connect_signals(ui)
		await _offer(ui,t,first,snapshot,target[0]+":first",true)
		var generation: int = ui._growth_generation
		var same := first.duplicate(true)
		same.view_revision += 1
		same.active_offer.selected_option_id = same.active_offer.options[1].option_id
		var signal_count := signals.size()
		ui.present_progression(same)
		await _settle(t)
		t.check(ui._growth_generation==generation and signals.size()==signal_count,target[0]+": same-offer focus revision retains its no-rebuild/no-signal fast path")
		_capture(ui,target[0]+":same_offer")
		await _offer(ui,t,next,sim.snapshot(state),target[0]+":next")
		# Deliberate presentation-only arrangements, never relabelled Core offers.
		var arranged := next.duplicate(true)
		arranged.active_offer.offer_id += ":one_no_target"
		arranged.active_offer.options = arranged.active_offer.options.slice(0,1)
		arranged.active_offer.selected_option_id = arranged.active_offer.options[0].option_id
		arranged.target = {}
		await _offer(ui,t,arranged,ui._snapshot,target[0]+":one_no_target")
		var two := next.duplicate(true)
		two.active_offer.offer_id += ":evolution_disabled"
		two.active_offer.options = two.active_offer.options.slice(0,2)
		two.active_offer.options[0].kind = "evolution"
		two.active_offer.options[0].can_select = false
		two.active_offer.options[0].blocked_reason = "missing_weapon"
		two.active_offer.options[0].requirements = [{"kind":"seal","required":2,"current":1,"met":false}]
		two.active_offer.options[1].kind = "evolution"
		two.active_offer.options[1].status = "evolved"
		await _offer(ui,t,two,ui._snapshot,target[0]+":two_disabled_evolved")
		var long_view := next.duplicate(true)
		long_view.active_offer.offer_id += ":long_warning_tradeoff"
		long_view.active_offer.options[0].slot_warning = "이 선택으로 마지막 장비 슬롯이 채워집니다. ".repeat(8)
		long_view.active_offer.options[1].tradeoff_text = "이동 속도가 감소하고 공격력이 증가합니다. ".repeat(6)
		long_view.active_offer.options[2].effect_delta = {}
		long_view.active_offer.options[2].description = "멀리 있는 적에게 연속 공격을 가합니다. ".repeat(10)
		await _offer(ui,t,long_view,ui._snapshot,target[0]+":long_warning_tradeoff")
		var empty := next.duplicate(true)
		empty.active_offer.offer_id += ":empty_options"
		empty.active_offer.options = []
		empty.target = {}
		await _offer(ui,t,empty,ui._snapshot,target[0]+":empty_options")
		t.check(ui._buttons.is_empty(),target[0]+": zero-option arrangement leaves no active choice controls")
		await _offer(ui,t,first,snapshot,target[0]+":restore_real")
		ui._buttons[1].grab_focus()
		var detail_focus: String = ui.focused_semantic_id()
		ui.open_evolution_details("option:"+str(first.active_offer.options[0].option_id))
		await _settle(t)
		_capture(ui,target[0]+":detail")
		var rotated := Vector2i(450,800) if target[1].x>target[1].y else Vector2i(800,450)
		vp.size = rotated
		ui.reflow(rotated,Rect2i(11,17,rotated.x-22,rotated.y-34))
		await _settle(t)
		t.check(ui._mode=="evolution_detail",target[0]+": real reflow retains detail modal")
		_capture(ui,target[0]+":detail_rotated")
		ui.close_evolution_details()
		await _settle(t)
		t.check(ui.focused_semantic_id()==detail_focus,target[0]+": detail return restores the same semantic focus after rotation")
		_capture(ui,target[0]+":detail_return")
		vp.size = target[1]
		ui.reflow(target[1],target[2])
		await _settle(t)
		t.check(ui.focused_semantic_id()==detail_focus,target[0]+": growth rotation retains semantic focus")
		_capture(ui,target[0]+":growth_rotated")
		vp.free()
		await _settle(t)
