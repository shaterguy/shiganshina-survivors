extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var old = f.app
	old.start_run(42)
	var a = old.simulation
	var writer_fixture := S.make(t,f.directory)
	var writer = writer_fixture.app
	writer.request_resume()
	writer.request_end_run()
	t.check(writer.state.phase == "abandoned" and writer.game_save.settled_through_serial == 1,"terminal fixture uses actual city abandonment and settlement")
	old._save_checkpoint()
	t.check(old.state.phase == "abandoned" and old.simulation != a and old.simulation._streamed.readiness(old.state).ok,"newer terminal authority is adopted only with its own prepared Core")
	t.check(old.game_save == writer.game_save and old.ui._mode == "abandoned","terminal quarantine preserves full economic authority and result UI")
	old.free(); writer.free()
	var cold := S.make(t,f.directory)
	t.check(cold.app.state.phase == "abandoned" and cold.app.simulation._streamed.readiness(cold.app.state).ok,"cold terminal startup confirms actual prepared Core/state pair")
	t.check(cold.app.world._city_view.get("ok",false),"cold terminal result has correctly derived terrain")
	cold.app.free()
	var plain = S.Controller.new()
	t.check(plain._city_runtime == null and plain.save_store._directory == "user://saves","unconfigured shipped controller retains finite runtime and original save location")
	var provider := S.City.new()
	var other := S.City.new()
	var disk := S.Disk.new("/tmp/controller_unconfigured_unused")
	var runtime := S.Runtime.new(other,disk)
	t.check(not plain.configure_city_runtime(provider,runtime,disk,"/tmp/controller_unconfigured_unused").get("ok",false),"configuration refuses different provider object even with identical content")
	plain.free()
