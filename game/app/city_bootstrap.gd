extends Node
# Product entry point. Configure before Controller._ready can inspect or load
# saves. The Controller keeps its standalone finite contract for other callers.
const CityProvider = preload("res://game/director/streamed_chapter_provider.gd")
const PreparedRuntime = preload("res://game/app/prepared_city_runtime.gd")
const DeltaStore = preload("res://game/persistence/world_delta_store.gd")
const Controller = preload("res://game/app/run_controller.gd")
const KoreanTheme = preload("res://game/ui/korean_ui_theme.tres")

# Embedders must set dependencies before tree entry; production uses the
# existing canonical directory. No directory move, reset, or eager save load.
var save_directory := "user://saves"
var city_provider = CityProvider.new()
var startup_result: Dictionary = {}
var app

func _ready() -> void:
	if save_directory.is_empty():
		_fail("configuration_locked")
		return
	var world_store := DeltaStore.new(save_directory.path_join("world"))
	var runtime := PreparedRuntime.new(city_provider,world_store)
	var candidate := Controller.new()
	startup_result = candidate.configure_city_runtime(city_provider,runtime,world_store,save_directory)
	if not startup_result.get("ok",false):
		candidate.free()
		_fail(str(startup_result.get("error_code","content_mismatch")))
		return
	app = candidate
	app.name = "CityController"
	add_child(app)

func _fail(code: String) -> void:
	startup_result = {"ok":false,"error_code":code}
	var notice := Label.new()
	notice.name = "StartupFailure"
	notice.text = "도시 데이터를 준비하지 못했습니다.\n게임을 종료한 뒤 다시 실행해 주세요.\n저장 데이터는 변경하지 않았습니다.\n오류: %s" % code
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.theme = KoreanTheme
	notice.add_theme_font_size_override("font_size",16)
	add_child(notice)
	notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
