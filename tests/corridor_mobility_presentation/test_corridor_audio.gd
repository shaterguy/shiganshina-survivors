extends RefCounted
class Capture extends "res://game/presentation/audio_director.gd":
	var sounds: Array[String] = []
	func play_sound(id: String) -> void: sounds.append(id)
func run(t) -> void:
	var audio := Capture.new()
	var snapshot := {"run_id":"corridor-audio","active_tick":1,"player":{"position":[0.0,0.0]},"entities":[],"player_mobility":{"schema_version":2,"cast_id":0,"phase":"ground"}}
	audio._present_foley(snapshot)
	snapshot.active_tick = 2; snapshot.player_mobility = {"schema_version":2,"cast_id":1,"phase":"boost"}
	var bytes := var_to_bytes(snapshot)
	audio._present_foley(snapshot)
	t.check(var_to_bytes(snapshot) == bytes,"audio observation leaves mobility snapshot unchanged")
	t.check(audio.sounds == ["wire_launch","gas"],"corridor activation emits one wire launch and pressure burst")
	audio._present_foley(snapshot)
	t.check(audio.sounds.size() == 2,"same tick does not replay activation audio")
	snapshot.active_tick = 3; audio._present_foley(snapshot)
	t.check(audio.sounds.size() == 2,"continued boost is silent without repeated launches")
	snapshot.active_tick = 4; snapshot.player_mobility.phase = "ground"; audio._present_foley(snapshot)
	t.check(audio.sounds == ["wire_launch","gas","wire_release"],"corridor completion releases wires without a heavy roof landing")
	snapshot.active_tick = 5; audio._present_foley(snapshot)
	t.check(audio.sounds.size() == 3,"ground continuation does not repeat release")
	snapshot.active_tick = 6; snapshot.player_mobility.cast_id = 2; snapshot.player_mobility.phase = "boost"; audio._present_foley(snapshot)
	snapshot.active_tick = 7; snapshot.player_mobility.phase = "ground"; audio._present_foley(snapshot)
	t.check(audio.sounds.count("wire_launch") == 2 and audio.sounds.count("wire_release") == 2 and not audio.sounds.has("land"),"repeat and interrupted boosts retain one activation and release each")
	audio.sounds.clear(); snapshot.run_id = "restored"; snapshot.player_mobility.phase = "boost"; audio._present_foley(snapshot)
	t.check(audio.sounds.is_empty(),"restored in-flight sample establishes audio baseline without replaying launch")
	snapshot.active_tick = 2; audio._present_foley(snapshot)
	t.check(audio.sounds.is_empty(),"clock rollback never invents activation or landing")
	audio.free()
