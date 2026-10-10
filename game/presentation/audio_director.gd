class_name GameAudioDirector
extends Node
var _assets: Dictionary = {}
var _streams: Dictionary = {}
var _last_played: Dictionary = {}
var _voices: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _music_id := ""
func _ready() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	if manifest is Dictionary: _assets = manifest.get("assets",{})
	_music = AudioStreamPlayer.new()
	_music.volume_db = -8
	add_child(_music)
	for index in range(8):
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -6
		add_child(voice)
		_voices.append(voice)
func sound_for_event(event: Dictionary) -> String:
	var payload: Dictionary = event.get("payload",{})
	match event.get("type",""):
		"damage":
			if str(payload.get("target_id","")) == "player": return "hurt"
			var source := str(payload.get("source_id",""))
			return "cannon" if source == "wall_cannon" else ("gas" if source == "odm_dash" else "slash")
		"upgrade_opened": return "level_up"
		"upgrade_applied": return "select"
		"xp_gained": return "xp"
		"boss_spawned": return "boss_spawn"
		"boss_defeated": return "hit"
		"run_ended": return "victory" if payload.get("result","") == "won" else "death"
	return ""
func consume_events(events: Array[Dictionary]) -> void:
	for event in events: play_sound(sound_for_event(event))
func play_sound(id: String) -> void:
	if id.is_empty(): return
	var now := Time.get_ticks_msec()
	if now-int(_last_played.get(id,-1000)) < 70: return
	var stream := _stream(id)
	if stream == null: return
	for voice in _voices:
		if not voice.playing:
			voice.stream = stream
			voice.play()
			_last_played[id] = now
			return
func present(snapshot: Dictionary) -> void:
	if not is_instance_valid(_music): return
	var desired := ""
	if not snapshot.is_empty() and not snapshot.phase in ["dead","won"]:
		desired = "boss_loop" if snapshot.phase == "evacuation" else "combat_loop"
		for enemy in snapshot.entities:
			if not str(enemy.get("boss_id","")).is_empty(): desired = "boss_loop"
	if desired != _music_id:
		_music.stop()
		_music_id = desired
		_music.stream = _stream(desired)
		if _music.stream != null: _music.play()
	_music.stream_paused = not snapshot.get("pause_reasons",[]).is_empty()
func _stream(id: String) -> AudioStream:
	if id.is_empty() or not _assets.has(id): return null
	if _streams.has(id): return _streams[id]
	var record: Dictionary = _assets[id]
	if record.get("kind","") != "audio" or not ResourceLoader.exists(record.path): return null
	var stream = load(record.path)
	if not stream is AudioStream: return null
	if stream is AudioStreamWAV and record.get("loop",false):
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(float(record.duration_seconds)*int(record.sample_rate))
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
