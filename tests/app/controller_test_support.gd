extends RefCounted
# NEW test assembly against real Core and real GameSaveStore, never a fake validator.
const Controller = preload("res://game/app/run_controller.gd")
const Save = preload("res://game/persistence/game_save_store.gd")
const Simulation = preload("res://game/core/run_simulation.gd")
const Fixture = preload("res://tests/core/core_fixture.gd")
static var _sequence := 0

func make(t) -> Dictionary:
	_sequence += 1
	var directory := "user://rebuild_controller_%d_%d_%d/saves" % [OS.get_process_id(),Time.get_ticks_usec(),_sequence]
	return {"app":restart(t,directory),"directory":directory}

func restart(t,directory: String):
	var app = Controller.new()
	var validator = Simulation.new()
	# Keep validation cache separate from the active simulation and retain its owner.
	app.set_meta("test_validation_core",validator)
	app.save_store = Save.new(directory,Callable(validator,"restore"))
	t.root.add_child(app)
	app.set_process(false)
	app.world.set_process(false)
	return app

func evolution_offer(app) -> void:
	# Arranged pre-boss build; the actual Core performs spawn, hit, reward and offer.
	var ready := Fixture.evolution_ready_state(app.simulation,app.chapter,app.state.run_config,int(app.state.seed))
	if ready.is_empty():
		push_error("real evolution fixture construction failed")
		return
	var candidate: Dictionary = app.game_save.duplicate(true)
	candidate.checkpoint = ready
	var committed: Dictionary = app.save_store.commit_game(candidate,int(candidate.store_revision))
	if not committed.get("ok",false):
		push_error("real evolution fixture commit failed: "+str(committed.get("error_code","")))
		return
	app._install_authority(committed.game_save)
	app.state = app.game_save.checkpoint.duplicate(true)
	app.pending_checkpoint.clear()
	app._present()
