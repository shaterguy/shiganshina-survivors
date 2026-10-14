extends RefCounted
const Router = preload("res://tests/gamepad_orientation/fake_android_router.gd")
func run(t) -> void:
	var startup := Router.new()
	startup.startup_devices = [7,9]
	startup.current_orientation = DisplayServer.SCREEN_SENSOR_PORTRAIT
	t.root.add_child(startup)
	t.check(startup.orientation_requests == [DisplayServer.SCREEN_REVERSE_LANDSCAPE],"already-connected controllers request landscape at tree entry without a button press")
	t.check(startup.orientation_reads == 1,"startup captures the preceding orientation policy only once")
	startup._on_connection(7,true)
	startup._on_connection(9,true)
	startup._on_connection(7,false)
	startup._on_connection(7,false)
	t.check(startup.orientation_requests == [DisplayServer.SCREEN_REVERSE_LANDSCAPE],"duplicates and removal of one of two controllers cannot restore portrait or repeat a rotation")
	startup._on_connection(9,false)
	t.check(startup.orientation_requests == [DisplayServer.SCREEN_REVERSE_LANDSCAPE,DisplayServer.SCREEN_SENSOR_PORTRAIT],"last disconnect restores the captured runtime policy rather than a hardcoded project default")
	startup._on_connection(9,false)
	t.check(startup.orientation_requests.size() == 2,"duplicate final disconnect has no orientation side effect")
	startup.free()
	var hotplug := Router.new()
	t.root.add_child(hotplug)
	t.check(hotplug.orientation_requests.is_empty() and hotplug.orientation_reads == 0,"touch-only startup leaves orientation untouched")
	var actions: Array[String] = []
	hotplug.ui_action.connect(func(action): actions.append(action))
	hotplug.set_active(false)
	Input.joy_connection_changed.emit(42,true)
	t.check(hotplug.orientation_requests == [DisplayServer.SCREEN_REVERSE_LANDSCAPE],"real subscribed connection signal requests landscape even when gameplay input is disabled")
	t.check(actions.is_empty() and hotplug.sample_move() == Vector2.ZERO,"connecting a controller emits no gameplay or menu action")
	Input.joy_connection_changed.emit(43,true)
	Input.joy_connection_changed.emit(999,false)
	Input.joy_connection_changed.emit(42,false)
	t.check(hotplug.orientation_requests.size() == 1,"unrelated and partial disconnects leave another connected controller in landscape")
	Input.joy_connection_changed.emit(43,false)
	t.check(hotplug.orientation_requests == [DisplayServer.SCREEN_REVERSE_LANDSCAPE,DisplayServer.SCREEN_SENSOR],"hotplug round-trip restores sensor policy")
	hotplug.current_orientation = DisplayServer.SCREEN_REVERSE_PORTRAIT
	Input.joy_connection_changed.emit(50,true)
	Input.joy_connection_changed.emit(50,false)
	t.check(hotplug.orientation_requests.slice(2) == [DisplayServer.SCREEN_REVERSE_LANDSCAPE,DisplayServer.SCREEN_REVERSE_PORTRAIT] and hotplug.orientation_reads == 2,"later connection captures a new intervening user policy")
	hotplug.free()
	var desktop := Router.new()
	desktop.orientation_supported = false
	desktop.startup_devices = [1]
	t.root.add_child(desktop)
	desktop._on_connection(2,true)
	desktop._on_connection(1,false)
	desktop._on_connection(2,false)
	t.check(desktop.orientation_reads == 0 and desktop.orientation_requests.is_empty(),"non-Android platform boundary never reads or writes screen orientation")
	desktop.free()

	for prior in [DisplayServer.SCREEN_LANDSCAPE, DisplayServer.SCREEN_SENSOR_LANDSCAPE, DisplayServer.SCREEN_REVERSE_LANDSCAPE]:
		var fixed := Router.new()
		fixed.current_orientation = prior
		t.root.add_child(fixed)
		fixed._on_connection(71,true)
		t.check(fixed.current_orientation == DisplayServer.SCREEN_REVERSE_LANDSCAPE,"controller fixes phone-top-right orientation from each landscape policy")
		fixed._on_connection(71,false)
		t.check(fixed.current_orientation == prior,"last disconnect restores exact preceding landscape policy")
		t.check(fixed.orientation_requests.size() == (0 if prior == DisplayServer.SCREEN_REVERSE_LANDSCAPE else 2),"already fixed reverse landscape is a no-op")
		fixed.free()
