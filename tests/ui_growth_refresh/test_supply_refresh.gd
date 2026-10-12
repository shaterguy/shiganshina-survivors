extends RefCounted
# Regression: a supply-only ACK must not replace a pressed growth control.
# Removing the upgrade guard in GameUI.present_supply must fail this suite.
const Fixture = preload("res://tests/core/new_current_regression_fixture.gd")
const SupplyFixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const View = preload("res://game/progression/progression_view.gd")
const UI = preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
 for frame in range(6): await t.process_frame
func _mouse(point: Vector2, pressed: bool) -> InputEventMouseButton:
 var event := InputEventMouseButton.new()
 event.position=point;event.global_position=point
 event.button_index=MOUSE_BUTTON_LEFT
 event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
 event.pressed=pressed
 return event
func _ids(ui) -> Array:
 return ui._buttons.map(func(button): return button.get_instance_id())
func _button(ui,id: String):
 for button in ui._buttons:
  if str(button.get_meta("semantic_id",""))==id:return button
 return null
func run(t) -> void:
 var sim=Fixture.simulation(t)
 var state=Fixture.earn_offer(sim,21,24)
 var viewport:=SubViewport.new();viewport.size=Vector2i(800,450);t.root.add_child(viewport)
 var ui=UI.new();viewport.add_child(ui)
 var supply: Dictionary=SupplyFixture.new().supply_view("affordable")
 ui.present_supply(supply)
 ui.present(sim.snapshot(state));ui.present_progression(View.new().build(state))
 ui.reflow(viewport.size,Rect2i(Vector2i.ZERO,viewport.size))
 ui.upgrade_focus_changed.connect(func(id):sim.set_offer_focus(state,id))
 var choices: Array=[]
 ui.upgrade_chosen.connect(func(offer,id):choices.append([offer,id]))
 await _settle(t)
 var option_id: String=state.upgrade_offer.options[2].option_id
 var pressed: Button=_button(ui,option_id)
 var point:=pressed.get_global_rect().get_center()
 viewport.push_input(_mouse(point,true),true)
 t.check(pressed.is_pressed(),"real GUI pointer down holds the growth card")
 ui.present_progression(View.new().build(state))
 var ids:=_ids(ui)
 var instance_id:=pressed.get_instance_id()
 var before: Dictionary=state.duplicate(true)
 var growth_before: Dictionary=ui._growth_view.duplicate(true)
 var fresh:=supply.duplicate(true);fresh.view_revision+=1;fresh.store_revision+=1;fresh.balance+=7
 var dto_before:=fresh.duplicate(true)
 ui.present_supply(fresh)
 t.check(_ids(ui)==ids,"supply-only ACK preserves every upgrade card/detail Control instance")
 t.check(viewport.gui_get_focus_owner()!=null and viewport.gui_get_focus_owner().get_instance_id()==instance_id,"supply-only ACK preserves actual GUI focus owner")
 t.check(is_instance_valid(pressed) and pressed.is_inside_tree() and pressed.is_pressed(),"supply-only ACK preserves the held pointer press")
 t.check(ui._growth_view==growth_before and state==before,"supply-only ACK does not change growth DTO or Core authority")
 t.check(ui._supply_view==fresh and fresh==dto_before,"supply-only ACK retains current supply data without mutating input")
 await _settle(t)
 viewport.push_input(_mouse(point,false),true)
 await _settle(t)
 t.check(choices==[[state.upgrade_offer.offer_id,option_id]],"release after supply ACK emits exactly the original current growth choice")
 fresh.balance=999
 t.check(ui._supply_view.balance==dto_before.balance,"retained supply DTO is independent of later caller mutation")
 # Settled request bookkeeping must still run before the upgrade fast path.
 ui._request_purchase("field_bandage",int(dto_before.view_revision))
 ui.present_action_result({"action":"purchase","ok":true})
 ui.present_supply(dto_before)
 t.check(ui._supply_locked,"same authority revision keeps a settled supply request locked")
 var settled:=dto_before.duplicate(true);settled.view_revision+=1
 ui.present_supply(settled)
 t.check(not ui._supply_locked and ui._last_action_result.is_empty(),"new authority revision unlocks a settled request during growth")
 t.check(_ids(ui)==ids,"unlock bookkeeping still does not rebuild growth controls")
 viewport.free()
 await _visible_supply_refresh(t,supply,"shop")
 await _visible_supply_refresh(t,supply,"loadout")
func _visible_supply_refresh(t,supply: Dictionary,mode: String) -> void:
 var viewport:=SubViewport.new();viewport.size=Vector2i(800,450);t.root.add_child(viewport)
 var ui=UI.new();viewport.add_child(ui)
 ui.present_supply(supply)
 if mode=="shop":ui.open_supply_shop()
 else:ui.open_loadout()
 await _settle(t)
 var old_panel_id: int=ui._supply_panel.get_instance_id()
 if mode=="shop":ui._supply_panel._purchase("field_bandage")
 else:ui._supply_panel._request_start()
 t.check(ui._supply_locked and ui._supply_waiting_result,mode+" request holds the real in-flight lock")
 ui.present_action_result({"action":"purchase" if mode=="shop" else "run_start","ok":true})
 var fresh:=supply.duplicate(true);fresh.view_revision+=1;fresh.store_revision+=1;fresh.balance=25
 ui.present_supply(fresh)
 await _settle(t)
 t.check(ui._mode==mode and ui._supply_panel.get_instance_id()!=old_panel_id,mode+" visible controls refresh on new supply authority")
 t.check(not ui._supply_locked and not ui._supply_waiting_result,mode+" new authority unlocks settled request")
 t.check(ui._supply_panel._view==fresh,mode+" visible panel uses the latest exact supply DTO")
 t.check(ui._supply_panel.action_buttons().any(func(button):return not button.disabled),mode+" actions rearm after settled save")
 viewport.free()
