class_name GameAudioDirector
extends Node
# Licensed Foley and independently authored scores share one bounded pool.
# Core events and snapshots are read-only; audio never consumes simulation RNG.
const EVOLUTION_SOUNDS := {
	"evo_wing_cut":{"base":"blade_slash","id":"evo_wing_cut"},
	"evo_crossfire":{"base":"wall_cannon","id":"evo_crossfire"},
	"evo_storm_chain":{"base":"chain_lightning","id":"evo_storm_chain"},
	"evo_inferno_zone":{"base":"fire_zone","id":"evo_inferno_zone"},
	"evo_whirlwind":{"base":"spin_slash","id":"evo_whirlwind"},
	"evo_sky_lance":{"base":"odm_dash","id":"evo_sky_lance"},
	"evo_echo_assault":{"base":"reentry_combo","id":"evo_echo_assault"},
	"evo_wing_squad":{"base":"ally_cover","id":"evo_wing_squad"}
}
const BASIC_SOUNDS := {"blade_slash":"slash","spin_slash":"spin_slash","odm_dash":"gas","reentry_combo":"reentry_combo","wall_cannon":"cannon","ally_cover":"ally_cover","chain_lightning":"chain_lightning","fire_zone":"fire_zone","player_mobility":"slash"}
const VARIANT_FAMILIES := ["slash","hit","hurt","step","titan_step","gas","wire_launch","armor_block"]
const PRIORITIES := {"step":10,"titan_step":25,"xp":15,"gas":35,"wire_launch":45,"wire_release":35,"land":40,"select":75,"cancel":75,"level_up":80,"boss_spawn":90,"hurt":95,"heal":85,"death":100,"victory":100,"armor_block":55,"structure_break":65}
const COOLDOWNS := {"step":180,"titan_step":350,"xp":140,"gas":150,"wire_launch":120,"wire_release":120,"land":120,"select":85,"cancel":85,"level_up":250,"boss_spawn":450,"hurt":120,"heal":250,"death":1000,"victory":1000,"cannon":110,"structure_break":150}
var _assets: Dictionary = {}
var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _variant_cursor: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _voice_priorities: Array[int] = []
var _voice_started: Array[int] = []
var _music: AudioStreamPlayer
var _music_id := ""
var _event_run := ""
var _event_seq := 0
var _load_us := 0
var _foley_run := ""
var _foley_tick := -1
var _mobility_cast := 0
var _mobility_phase := "ground"
var _player_step_tick := 0
var _titan_step_tick := 0
var _player_position := Vector2.ZERO
func _ready() -> void:
	var started := Time.get_ticks_usec()
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	if manifest is Dictionary: _assets = manifest.get("assets",{})
	var mix := _ensure_bus("WingsMix","Master",0.0)
	if AudioServer.get_bus_effect_count(mix) == 0:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = -1.0
		limiter.release = 0.08
		AudioServer.add_bus_effect(mix,limiter)
	_ensure_bus("WingsSFX","WingsMix",-4.0)
	_ensure_bus("WingsMusic","WingsMix",0.0)
	_music = AudioStreamPlayer.new()
	_music.bus = &"WingsMusic"
	_music.volume_db = -10.0
	add_child(_music)
	for index in range(8):
		var voice := AudioStreamPlayer.new()
		voice.bus = &"WingsSFX"
		voice.volume_db = -7.0
		add_child(voice)
		_voices.append(voice)
		_voice_priorities.append(-1)
		_voice_started.append(0)
	# Fixed bank, loaded at presentation initialization, never a first-hit burst.
	for id in _assets:
		if _assets[id].get("kind","") == "audio": _stream(str(id))
	_load_us = Time.get_ticks_usec()-started
func _ensure_bus(name: String, send: String, volume: float) -> int:
	var index := AudioServer.get_bus_index(name)
	if index < 0:
		AudioServer.add_bus()
		index = AudioServer.bus_count-1
		AudioServer.set_bus_name(index,name)
	AudioServer.set_bus_send(index,send)
	AudioServer.set_bus_volume_db(index,volume)
	return index
func sound_for_event(event: Dictionary) -> String:
	var payload: Dictionary = event.get("payload",{})
	match event.get("type",""):
		"player_attack": return str(sound_profile_for_event(event).get("id",""))
		"damage":
			if str(payload.get("target_id","")) == "player": return "hurt"
			return str(BASIC_SOUNDS.get(str(payload.get("source_id","")),"hit"))
		"armor_blocked": return "armor_block"
		"projectile_impact": return "cannon" if str(payload.get("base_item_id","")) == "wall_cannon" else "hit"
		"structure_destroyed": return "structure_break"
		"structure_damaged": return "hit"
		"supply_used": return "heal"
		"upgrade_opened": return "level_up"
		"upgrade_applied": return "level_up" if payload.get("kind","") == "evolution" else "select"
		"xp_gained": return "xp"
		"boss_spawned": return "boss_spawn"
		"boss_defeated": return "cannon"
		"run_ended":
			match payload.get("result",""):
				"won": return "victory"
				"dead": return "death"
				"abandoned": return "cancel"
	return ""
func sound_profile_for_event(event: Dictionary) -> Dictionary:
	var payload: Dictionary = event.get("payload",{})
	if event.get("type","") != "player_attack" or payload.get("phase","") != "executed": return {}
	var evo := str(payload.get("evolution_id",""))
	var base := str(payload.get("base_item_id",""))
	var stage := maxi(0,int(payload.get("stage_index",0)))
	if not evo.is_empty():
		if not EVOLUTION_SOUNDS.has(evo) or base != EVOLUTION_SOUNDS[evo].base: return {}
		var evolved_id := _variant(str(EVOLUTION_SOUNDS[evo].id),stage%3)
		var profile := {"id":evolved_id,"pitch_scale":1.0,"volume_db":-7.0,"priority":65,"cooldown_ms":70,"throttle_key":evo+":"+str(stage%3)}
		if evo == "evo_inferno_zone" and int(payload.get("stage_count",0)) > 0 and stage == int(payload.stage_count)-1:
			profile.merge({"id":"cannon","priority":75,"volume_db":-6.0,"throttle_key":evo+":eruption"},true)
		return profile
	var id := str(BASIC_SOUNDS.get(base,"slash" if base.begins_with("character:") else ""))
	if id.is_empty(): return {}
	var variant := maxi(0,_sequence(event)-1)%3 if id in VARIANT_FAMILIES else 0
	return {"id":_variant(id,variant),"pitch_scale":1.0,"volume_db":-7.0,"priority":50,"cooldown_ms":int(COOLDOWNS.get(id,70)),"throttle_key":id}
func _variant(id: String, index: int) -> String:
	return id if index == 0 else id+"_v"+str(index+1)
func consume_events(events: Array[Dictionary]) -> void:
	var ordered := events.duplicate()
	ordered.sort_custom(func(a,b): return _sequence(a) < _sequence(b))
	var accepted: Array[Dictionary] = []
	var authored_attacks: Dictionary = {}
	for event in ordered:
		if not _accept_event(event): continue
		accepted.append(event)
		if not sound_profile_for_event(event).is_empty():
			var attack_id := str(event.get("payload",{}).get("attack_id",""))
			if not attack_id.is_empty(): authored_attacks[attack_id] = true
	for event in accepted:
		var payload: Dictionary = event.get("payload",{})
		# One authored stage is independent of target count. Player hurt always
		# remains eligible and can preempt footsteps at the fixed voice limit.
		if event.get("type") in ["damage","projectile_impact"] and str(payload.get("target_id","")) != "player" and authored_attacks.has(str(payload.get("attack_id",""))): continue
		var profile := sound_profile_for_event(event)
		if profile.is_empty(): play_sound(sound_for_event(event))
		else: _play_profile(profile)
func _sequence(event: Dictionary) -> int:
	var id := str(event.get("event_id",""))
	var suffix := id.get_slice(":",id.get_slice_count(":")-1)
	return int(suffix) if suffix.is_valid_int() else -1
func _accept_event(event: Dictionary) -> bool:
	var sequence := _sequence(event)
	if sequence < 0: return true
	var id := str(event.event_id)
	var run := id.substr(0,id.rfind(":"))
	if run != _event_run:
		_event_run = run
		_event_seq = 0
	if sequence <= _event_seq: return false
	_event_seq = sequence
	return true
func reset_presentation() -> void:
	_last_played.clear()
	_variant_cursor.clear()
	_event_run = ""
	_event_seq = 0
	_foley_run = ""
	_foley_tick = -1
	_mobility_cast = 0
	_mobility_phase = "ground"
	_music_id = ""
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
		_music.stream_paused = false
	for index in _voices.size():
		_voices[index].stop()
		_voices[index].stream = null
		_voices[index].stream_paused = false
		_voice_priorities[index] = -1
		_voice_started[index] = 0
func play_sound(id: String) -> void:
	if id.is_empty(): return
	var index := int(_variant_cursor.get(id,0))%3 if id in VARIANT_FAMILIES else 0
	var volume := -14.0 if id in ["xp","step"] else (-11.0 if id in ["select","cancel","titan_step"] else -7.0)
	if id in ["hurt","boss_spawn","death","victory"]: volume = -6.0
	if _play_profile({"id":_variant(id,index),"pitch_scale":1.0,"volume_db":volume,"priority":int(PRIORITIES.get(id,50)),"cooldown_ms":int(COOLDOWNS.get(id,70)),"throttle_key":id}):
		if id in VARIANT_FAMILIES: _variant_cursor[id] = (index+1)%3
func _voice_slot(priority: int) -> int:
	var selected := -1
	for index in _voices.size():
		if not _voices[index].playing: return index
		if selected < 0 or _voice_priorities[index] < _voice_priorities[selected] or (_voice_priorities[index] == _voice_priorities[selected] and _voice_started[index] < _voice_started[selected]): selected = index
	if selected < 0: return -1
	if priority > _voice_priorities[selected]: return selected
	# Renew equal-priority combat tails after the initial transient; a same-frame
	# burst cannot erase every attack, and long cannon tails cannot lock the pool.
	if priority == _voice_priorities[selected] and priority < 90 and Time.get_ticks_msec()-_voice_started[selected] >= 90: return selected
	return -1
func _play_profile(profile: Dictionary) -> bool:
	var id := str(profile.get("id",""))
	if id.is_empty(): return false
	var key := str(profile.get("throttle_key",id))
	var now := Time.get_ticks_msec()
	if now-int(_last_played.get(key,-10000)) < int(profile.get("cooldown_ms",70)): return false
	var stream := _stream(id)
	if stream == null: return false
	var priority := int(profile.get("priority",50))
	var index := _voice_slot(priority)
	if index < 0: return false
	var voice := _voices[index]
	voice.stop()
	voice.stream = stream
	voice.pitch_scale = float(profile.get("pitch_scale",1.0))
	voice.volume_db = float(profile.get("volume_db",-7.0))
	voice.stream_paused = false
	voice.play()
	_voice_priorities[index] = priority
	_voice_started[index] = now
	_last_played[key] = now
	return true
func present(snapshot: Dictionary, suspended: bool = false) -> void:
	if not is_instance_valid(_music): return
	var desired := "menu_loop" if snapshot.is_empty() else ""
	if not snapshot.is_empty() and not snapshot.phase in ["dead","won","abandoned"]:
		desired = "boss_loop" if snapshot.phase == "evacuation" else "combat_loop"
		for enemy in snapshot.get("entities",[]):
			if not str(enemy.get("boss_id","")).is_empty():
				desired = "boss_loop"
				break
	if desired != _music_id:
		_music.stop()
		_music_id = desired
		_music.stream = _stream(desired)
		if _music.stream != null: _music.play()
	_music.stream_paused = suspended or not snapshot.get("pause_reasons",[]).is_empty()
	if snapshot.is_empty() or snapshot.get("phase","") in ["dead","won","abandoned"] or _music.stream_paused: return
	_present_foley(snapshot)
func _present_foley(snapshot: Dictionary) -> void:
	var tick := int(snapshot.get("active_tick",0))
	var run := str(snapshot.get("run_id",""))
	var player: Dictionary = snapshot.get("player",{})
	var raw_position: Array = player.get("position",[0.0,0.0])
	var position := Vector2(float(raw_position[0]),float(raw_position[1]))
	var mobility: Dictionary = snapshot.get("player_mobility",{})
	var cast := int(mobility.get("cast_id",0))
	var phase := str(mobility.get("phase","ground"))
	if _foley_tick < 0 or run != _foley_run or tick < _foley_tick:
		_foley_run = run
		_foley_tick = tick
		_mobility_cast = cast
		_mobility_phase = phase
		_player_step_tick = tick
		_titan_step_tick = tick
		_player_position = position
		return
	if tick <= _foley_tick: return
	if cast != _mobility_cast and phase != "ground":
		play_sound("wire_launch")
		play_sound("gas")
	if phase == "land" and _mobility_phase not in ["land","ground"]: play_sound("wire_release")
	if phase == "ground" and _mobility_phase != "ground": play_sound("land")
	if phase == "ground" and tick-_player_step_tick >= 18 and position.distance_squared_to(_player_position) > 0.01:
		play_sound("step")
		_player_step_tick = tick
	if tick-_titan_step_tick >= 30:
		# One nearest audible moving actor per cadence, independent of crowd size.
		_titan_step_tick = tick
		var nearest := 420.0*420.0
		var found := false
		for enemy in snapshot.get("entities",[]):
			if float(enemy.get("hp",1.0)) <= 0: continue
			var velocity: Array = enemy.get("velocity",[0.0,0.0])
			if absf(float(velocity[0]))+absf(float(velocity[1])) < 0.01: continue
			var point: Array = enemy.get("position",[1000000.0,1000000.0])
			var distance := position.distance_squared_to(Vector2(float(point[0]),float(point[1])))
			if distance < nearest:
				nearest = distance
				found = true
		if found:
			var variant := int(_variant_cursor.get("titan_step",0))%3
			if _play_profile({"id":_variant("titan_step",variant),"priority":25,"volume_db":lerpf(-10.0,-22.0,sqrt(nearest)/420.0),"throttle_key":"titan_step","cooldown_ms":350}): _variant_cursor["titan_step"] = (variant+1)%3
	_foley_tick = tick
	_mobility_cast = cast
	_mobility_phase = phase
	_player_position = position
func _stream(id: String) -> AudioStream:
	if id.is_empty() or not _assets.has(id): return null
	if _streams.has(id): return _streams[id]
	var record: Dictionary = _assets[id]
	if record.get("kind","") != "audio" or not ResourceLoader.exists(record.path): return null
	var stream = load(record.path)
	if not stream is AudioStream: return null
	if record.get("loop",false):
		stream = stream.duplicate()
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = roundi(float(record.duration_seconds)*int(record.sample_rate))
		elif stream is AudioStreamOggVorbis:
			stream.loop = true
			stream.loop_offset = 0.0
	_streams[id] = stream
	return stream
func _exit_tree() -> void:
	if is_instance_valid(_music):
		_music.stop()
		_music.stream = null
	for voice in _voices:
		voice.stop()
		voice.stream = null
	_streams.clear()
