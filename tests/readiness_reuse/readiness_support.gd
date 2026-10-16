extends RefCounted
# Test-only arrangement. Mount under res://tests/readiness_reuse/.
# Real Controller/Core/helper/world and private unique user:// saves are reused.
const CitySupport = preload("res://tests/loot_city/loot_city_support.gd")
var city := CitySupport.new()

func make(t, label: String, roles: Array = ["grabber"]):
	var app = city.make(t,"readiness_"+label)
	if app == null: return null
	app.state.player.attack_ready_ticks = {"blade_slash":1000000}
	var events: Array[Dictionary] = []
	for index in roles.size():
		var command := {"command_id":"readiness:setup:"+str(index),"kind":"spawn_enemy","origin_revision":int(app.state.world.origin_revision),"payload":{"entity_id":"readiness:role:"+str(index),"enemy_id":roles[index],"position":[640.0,320.0+64.0*index],"spawned_tick":int(app.state.active_tick)}}
		app.simulation._apply_command(app.state,command,events)
	t.check(app.state.entities.size() == roles.size(),"READINESS: fixture admits every role through actual spawn")
	if app.state.entities.size() != roles.size(): app.free(); return null
	if not city.refresh(t,app,"role fixture "+label): app.free(); return null
	t.check(app.state.player_mobility.schema_version == 2,"READINESS: fixture uses actual schema-two mobility")
	return app

func point(state: Dictionary) -> Vector2:
	return Vector2(float(state.player.position[0]),float(state.player.position[1]))

func canonical(value: Variant) -> String:
	# Sorted keys, full precision. Both baseline and candidate use the same engine.
	return JSON.stringify(value,"",true,true)

func digest(value: Variant) -> String:
	return canonical(value).sha256_text()

func row(core, state: Dictionary, events: Array, index: int) -> Dictionary:
	var status: Dictionary = core.step_status()
	return {"index":index,"tick":int(state.active_tick),"state_sha256":digest(state),"events":JSON.parse_string(canonical(events)),"events_sha256":digest(events),"status":JSON.parse_string(canonical(status)),"rng_state":str(state.rng_state),"progression_rng_state":str(state.progression_rng_state),"attack_view_sha256":digest(core.enemy_attack_view(state))}

func has_property(object: Object, name: String) -> bool:
	for property in object.get_property_list():
		if str(property.name) == name: return true
	return false

func counts(helper) -> int:
	return int(helper.get("qa_readiness_calls"))

func reset_count(helper) -> void:
	helper.set("qa_readiness_calls",0)

func dispose(t, app) -> void:
	# Outside trace/count observations. Follow the existing stress fixture's
	# explicit playback release rather than treating app.free() as mixer drain.
	app.set_process(false)
	app.world.set_process(false)
	var players: Array = [app.audio._music]
	players.append_array(app.audio._voices)
	var playbacks: Array[WeakRef] = []
	for player in players:
		if is_instance_valid(player) and player.has_stream_playback(): playbacks.append(weakref(player.get_stream_playback()))
	app.audio.reset_presentation()
	app.audio._streams.clear()
	var turnovers := 0
	var last_mix: float = AudioServer.get_time_since_last_mix()
	var deadline: int = Time.get_ticks_usec()+1000000
	while Time.get_ticks_usec() < deadline and (turnovers < 3 or _live_playbacks(playbacks) > 0):
		await t.create_timer(0.005,true,false,true).timeout
		var next_mix: float = AudioServer.get_time_since_last_mix()
		if next_mix < last_mix: turnovers += 1
		last_mix = next_mix
	var stopped := true
	for player in players:
		if is_instance_valid(player): stopped = stopped and not player.playing and player.stream == null
	t.check(stopped and turnovers >= 3 and _live_playbacks(playbacks) == 0,"READINESS: fixture audio release settles before disposal")
	players.clear()
	app.free()
	await t.process_frame
	await t.process_frame

func _live_playbacks(references: Array[WeakRef]) -> int:
	var alive := 0
	for reference in references:
		if reference.get_ref() != null: alive += 1
	return alive
