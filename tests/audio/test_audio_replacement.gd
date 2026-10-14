extends RefCounted
const Audio = preload("res://game/presentation/audio_director.gd")
func run(t) -> void:
	var a := Audio.new()
	t.root.add_child(a)
	await t.process_frame
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/manifest.json"))
	t.check(manifest.get("audio_revision",{}).get("id") == "recorded_foley_orchestral_v1","authored replacement revision is explicit")
	var audio_count := 0
	var sfx_bytes := 0
	var music_bytes := 0
	var paths: Dictionary = {}
	for id in manifest.assets:
		var r: Dictionary = manifest.assets[id]
		if r.get("kind") != "audio": continue
		audio_count += 1
		t.check(r.get("audio_revision") == "recorded_foley_orchestral_v1" and not r.get("source_layers",[]).is_empty(),"every sound replaced with licensed source layers "+id)
		t.check(not paths.has(r.path),"each authored sound owns distinct bytes "+id)
		paths[r.path] = true
		if r.path.ends_with(".wav"): sfx_bytes += FileAccess.get_file_as_bytes(r.path).size()
		else: music_bytes += FileAccess.get_file_as_bytes(r.path).size()
		t.check(a._stream(id) != null,"every registered sound decodes "+id)
	t.check(a._streams.size() == audio_count,"all audio is cached before combat presentation")
	t.check(sfx_bytes <= 12*1024*1024 and music_bytes <= 16*1024*1024,"bounded PCM and compressed-score cache footprint")
	for id in ["combat_loop","boss_loop","menu_loop"]:
		var s = a._stream(id)
		t.check(s is AudioStreamOggVorbis and s.loop and s.get_length() > 20,"real stereo score has looping OGG playback "+id)
	var ids: Dictionary = {}
	for evo in a.EVOLUTION_SOUNDS:
		var preset: Dictionary = a.EVOLUTION_SOUNDS[evo]
		var stage_ids: Dictionary = {}
		for stage in 3:
			var e := {"type":"player_attack","payload":{"phase":"executed","evolution_id":evo,"base_item_id":preset.base,"stage_index":stage}}
			var p: Dictionary = a.sound_profile_for_event(e)
			stage_ids[p.id] = true
			t.check(p.pitch_scale == 1.0 and a._stream(p.id) != null,"evolution uses authored layer variation rather than transpose "+evo)
			if stage == 0: ids[p.id] = true
		t.check(stage_ids.size() == 3,"three independently rendered evolution stages "+evo)
	t.check(ids.size() == 8,"eight distinct evolved sound families")
	for type in ["armor_blocked","supply_used","structure_destroyed","structure_damaged"]:
		t.check(not a.sound_for_event({"type":type,"payload":{}}).is_empty(),"previously silent material event now mapped "+type)
	a.reset_presentation()
	for i in 8:a._play_profile({"id":"step","priority":10,"volume_db":-15.0,"throttle_key":"capacity:%d"%i,"cooldown_ms":0})
	t.check(a._voices.filter(func(v):return v.playing).size() == 8,"eight-voice pool fills without expansion")
	a._play_profile({"id":"hurt","priority":90,"volume_db":-6.0,"throttle_key":"critical","cooldown_ms":0})
	t.check(a._voices.size() == 8 and a._voices.any(func(v):return v.playing and v.stream == a._stream("hurt")),"player hurt preempts low-priority footstep at full cap")
	var critical: AudioStreamPlayer = a._voices.filter(func(v):return v.playing and v.stream == a._stream("hurt"))[0]
	a._play_profile({"id":"step","priority":5,"throttle_key":"lower","cooldown_ms":0})
	t.check(critical.stream == a._stream("hurt") and not a._last_played.has("lower"),"low-priority crowd cannot steal or falsely admit a voice")
	a.reset_presentation()
	for i in 8:a._play_profile({"id":"cannon","priority":50,"throttle_key":"dense:%d"%i,"cooldown_ms":0})
	t.check(not a._play_profile({"id":"slash","priority":50,"throttle_key":"fresh-early","cooldown_ms":0}),"same-frame equal-priority burst preserves attack transients")
	# Actual-device clock diagnostic: a .11 SceneTree timer advanced only 13ms
	# of wall time after a long import/preload frame. Admission uses monotonic time.
	var admission_started := Time.get_ticks_msec()
	while Time.get_ticks_msec()-admission_started < 110:
		await t.create_timer(.01).timeout
	t.check(a._voices.all(func(v):return v.playing),"all eight cannon tails still play at real transient boundary")
	t.check(a._play_profile({"id":"slash","priority":50,"throttle_key":"fresh","cooldown_ms":0}),"fresh attack renews long equal-priority tail after transient")
	t.check(a._voices.size() == 8,"dense battle never expands pool")
	a.reset_presentation();a.play_sound("xp");a.play_sound("xp")
	t.check(a._voices.filter(func(v):return v.playing).size() == 1,"pickup cooldown prevents crowd spam")
	var b := AudioServer.get_bus_index("WingsMix")
	t.check(b >= 0 and AudioServer.get_bus_effect_count(b) == 1 and AudioServer.get_bus_effect(b,0) is AudioEffectHardLimiter,"sum bus has one real look-ahead safety limiter")
	t.check(a._music.bus == &"WingsMusic" and a._voices.all(func(v):return v.bus == &"WingsSFX"),"music and SFX use explicit gain buses")
	a.reset_presentation();a.present({})
	t.check(a._music_id == "menu_loop" and a._music.playing,"empty menu plays authored score")
	var snapshot := {"run_id":"audio-proof","active_tick":1,"phase":"survival","pause_reasons":[],"player":{"position":[0.,0.],"velocity":[150.,0.]},"entities":[],"player_mobility":{"cast_id":0,"phase":"ground"}}
	var unchanged := JSON.stringify(snapshot)
	a.present(snapshot)
	t.check(JSON.stringify(snapshot) == unchanged,"audio snapshot presentation is read-only")
	snapshot.active_tick = 2;snapshot.player_mobility = {"schema_version":2,"cast_id":1,"phase":"boost"};a.present(snapshot)
	t.check(a._last_played.has("wire_launch") and a._last_played.has("gas"),"accepted traversal starts wire and pressure sounds")
	snapshot.active_tick = 3;snapshot.player_mobility.phase = "boost";a.present(snapshot)
	snapshot.active_tick = 4;snapshot.player_mobility.phase = "ground";a.present(snapshot)
	t.check(a._last_played.has("wire_release"),"wire detachment has material feedback")
	snapshot.active_tick = 5;snapshot.player_mobility.phase = "ground";a.present(snapshot)
	t.check(not a._last_played.has("land"),"grounded corridor release never invents a roof landing impact")
	var before := a._last_played.duplicate(true);snapshot.pause_reasons = ["background"];snapshot.active_tick = 90;a.present(snapshot)
	t.check(a._last_played == before and a._music.stream_paused,"paused snapshots never emit movement or crowd Foley")
	snapshot.pause_reasons = [];snapshot.active_tick = 120
	a.present(snapshot,true)
	t.check(a._last_played == before and a._music.stream_paused,"controller suspension blocks Foley before post-presentation guard")
	a.reset_presentation()
	t.check(a._last_played.is_empty() and a._voices.all(func(v):return not v.playing and v.stream == null),"run adoption clears sounds and admission state")
	print("AUDIO_REPLACEMENT_CACHE "+JSON.stringify({"audio_count":audio_count,"sfx_bytes":sfx_bytes,"music_bytes":music_bytes,"load_microseconds":a._load_us}))
	a.free()
