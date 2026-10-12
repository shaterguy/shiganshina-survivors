extends RefCounted
# Removing evolution_detail from the supply-only fast path must invalidate
# a real held Back press and reset the reader's scroll position.
const Fixture=preload("res://tests/core/new_current_regression_fixture.gd")
const SupplyFixture=preload("res://tests/fixtures/evolution_supply_fixture.gd")
const View=preload("res://game/progression/progression_view.gd")
const UI=preload("res://game/ui/game_ui.gd")
func _settle(t) -> void:
 for frame in range(6):await t.process_frame
func _mouse(point: Vector2,pressed: bool) -> InputEventMouseButton:
 var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;e.pressed=pressed;return e
func run(t) -> void:
 var sim=Fixture.simulation(t)
 var state:Dictionary=Fixture.earn_offer(sim,21,24)
 var growth:Dictionary=View.new().build(state)
 for target in ["option:"+str(growth.active_offer.options[0].option_id),str(growth.target.evolution_id)]:
  var vp:=SubViewport.new();vp.size=Vector2i(568,320);t.root.add_child(vp)
  var ui=UI.new();vp.add_child(ui)
  var supply:Dictionary=SupplyFixture.new().supply_view("affordable")
  ui.present_supply(supply);ui.present(sim.snapshot(state));ui.present_progression(growth)
  ui.reflow(vp.size,Rect2i(16,12,536,296))
  ui._buttons[1].grab_focus()
  var return_focus:String=ui.focused_semantic_id()
  ui.open_evolution_details(target)
  await _settle(t)
  ui._scroll.scroll_vertical=100000
  await _settle(t)
  var scroll:int=ui._scroll.scroll_vertical
  t.check(scroll>0,"authored detail overflows the supported small landscape and is scrolled")
  var back:Button=ui._buttons[0]
  var back_id:=back.get_instance_id()
  t.check(ui._scroll.get_global_rect().grow(1).encloses(back.get_global_rect()),"scrolled detail exposes the real Back button")
  var point:=back.get_global_rect().get_center()
  vp.push_input(_mouse(point,true),true)
  t.check(back.is_pressed(),"real GUI pointer holds the detail Back button")
  var choices:Array=[]
  ui.upgrade_chosen.connect(func(offer,id):choices.append([offer,id]))
  var before:Dictionary=state.duplicate(true)
  var fresh:=supply.duplicate(true);fresh.view_revision+=1;fresh.store_revision+=1
  ui.present_supply(fresh)
  t.check(ui._buttons[0].get_instance_id()==back_id,"supply ACK preserves the detail Back Control")
  t.check(vp.gui_get_focus_owner()!=null and vp.gui_get_focus_owner().get_instance_id()==back_id,"supply ACK preserves the detail actual GUI focus owner")
  t.check(is_instance_valid(back) and back.is_inside_tree() and back.is_pressed(),"supply ACK preserves the detail held Back press")
  t.check(ui._scroll.scroll_vertical==scroll,"supply ACK preserves the reader's exact detail scroll")
  t.check(ui._detail_id==target and ui._return_focus_id==return_focus,"supply ACK preserves detail identity and return focus")
  t.check(ui._supply_view==fresh and ui._growth_view==growth and state==before,"detail ACK refreshes supply data without altering growth or authority")
  await _settle(t)
  vp.push_input(_mouse(point,false),true)
  await _settle(t)
  t.check(ui._mode=="upgrade" and ui._detail_id.is_empty(),"first release after ACK returns from detail to growth")
  t.check(ui.focused_semantic_id()==return_focus and choices.is_empty(),"Back restores the originating detail action without choosing growth")
  vp.free()
