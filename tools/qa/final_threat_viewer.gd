extends Node
# Explicit presentation fixture: fast-forwarded clock, not a full 30-minute playthrough.
const Controller = preload("res://game/app/run_controller.gd")
var viewport: SubViewport
var surface: SubViewportContainer
var game
func _ready() -> void:
	surface = SubViewportContainer.new()
	add_child(surface)
	viewport = SubViewport.new()
	viewport.size = Vector2i(800,450)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	surface.add_child(viewport)
	game = Controller.new()
	game.save_store = load("res://game/persistence/save_store.gd").new("user://final_qa_"+str(OS.get_process_id()))
	viewport.add_child(game)
	game.set_process(false)
	game.start_run(42)
	game.state.active_tick = 107999
	game.state.survival_tick = 107999
	game.simulation.step(game.state,Vector2.ZERO,game.director.plan(game.state,game.chapter))
	game._present()
	get_viewport().size_changed.connect(_fit)
	_fit()
	DisplayServer.window_set_title("Final-threat render fixture: R rotate, H warning, D dock, F9 capture")
func _fit() -> void:
	surface.size = Vector2(viewport.size)
	var size := get_viewport().get_visible_rect().size
	var factor := minf(size.x/viewport.size.x,size.y/viewport.size.y)
	surface.scale = Vector2.ONE*factor
	surface.position = (size-Vector2(viewport.size)*factor)*0.5
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_R:
		viewport.size = Vector2i(450,800) if viewport.size.y < viewport.size.x else Vector2i(800,450)
		_fit()
	if event.keycode == KEY_H:
		for index in range(150): game.simulation.step(game.state,Vector2.ZERO,game.director.plan(game.state,game.chapter))
	if event.keycode == KEY_D:
		game.state.player.position = [0.0,360.0]
	if event.keycode == KEY_F9: game._capture_validation_frame()
	game._present()
