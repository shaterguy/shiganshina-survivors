extends RefCounted
# Presentation contract fixture only; not a real terminal simulation proof.
const UI = preload("res://game/ui/game_ui.gd")
const Director = preload("res://game/director/spawn_director.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Fixture = preload("res://tests/fixtures/evolution_supply_fixture.gd")
const Audio = preload("res://game/presentation/audio_director.gd")

func run(t) -> void:
	var chapter: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	var base: Dictionary = Fixture.new().run_state()
	for phase in ["dead","won","abandoned"]:
		var state := base.duplicate(true)
		state.phase = phase
		state.active_tick = 119
		state.survival_tick = 119
		var before := state.duplicate(true)
		t.check(Director.new().plan(state,chapter).is_empty(),"director plans zero commands in terminal "+phase)
		var ui = UI.new()
		t.root.add_child(ui)
		ui.present(state)
		await t.process_frame
		t.check(ui._mode == phase,"UI uses distinct terminal mode "+phase)
		t.check(not ui._hint.visible and not ui._stick_base.visible,"terminal screen hides movement guidance "+phase)
		t.check(state == before,"terminal presentation does not mutate combat state "+phase)
		if phase == "abandoned":
			t.check(ui._title.text.contains("퇴각"),"abandoned outcome is not described as death or victory")
		ui.free()
		var audio = Audio.new()
		t.root.add_child(audio)
		audio.present(state)
		t.check(audio._music_id.is_empty(),"terminal outcome stops combat music "+phase)
		if phase == "abandoned":
			t.check(audio.sound_for_event({"type":"run_ended","payload":{"result":phase}}) == "cancel","retreat does not play a death sound")
		audio.free()
	await t.process_frame
