extends Node2D
# Explicit art QA only. No manifest, gameplay or user-save writes.
const WorldView = preload("res://game/presentation/world_view.gd")
const PNG_SHA := "e3b3fe2008cb4db79e8df72bf670dc6c87e37c81c055c85a1546fc47dc7ea427"
var selector = WorldView.new()
var record: Dictionary
var atlas: Texture2D
var elapsed := 0.0
var animation := "move"
var show_translation := false
var frozen := false
var caption: Label
func _ready() -> void:
	get_window().content_scale_size = Vector2i(800,540)
	get_window().size = Vector2i(800,540)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://docs/art/recovery-armored-v6-registration.json"))
	record = data.candidate_entry
	assert(FileAccess.get_sha256(record.path) == PNG_SHA)
	atlas = load(record.path)
	selector._assets = {"armored_titan":record}
	caption = Label.new()
	caption.position = Vector2(12,8)
	caption.add_theme_font_size_override("font_size",15)
	add_child(caption)
	DisplayServer.window_set_title("Recovered Armored v6 WALK QA - candidate only")
	_update_caption()
func _exit_tree() -> void:
	selector.free()
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_1: animation = "idle"; elapsed = 0.0
		KEY_2: animation = "move"; elapsed = 0.0
		KEY_3: animation = "attack"; elapsed = 0.0
		KEY_4: animation = "hit"; elapsed = 0.0
		KEY_T: show_translation = not show_translation; elapsed = 0.0
		KEY_SPACE: frozen = not frozen
	_update_caption()
	queue_redraw()
func _process(delta: float) -> void:
	if not frozen: elapsed += delta
	_update_caption()
	queue_redraw()
func _update_caption() -> void:
	caption.text = "QA candidate v6 WALK | scale 1.5 | state: %s | %.2fs\n1 idle / 2 walk / 3 attack / 4 hit / T fixed-ground travel / Space freeze\nTwo directions; source atlas unchanged. Travel wraps every two full cycles." % [animation,elapsed]
func _draw() -> void:
	if atlas == null: return
	draw_rect(Rect2(0,0,800,540),Color("202730"))
	for x in range(0,801,32): draw_line(Vector2(x,480),Vector2(x,536),Color("44515d"),1.0)
	draw_line(Vector2(0,480),Vector2(800,480),Color("afb8bd"),2.0)
	var scale_value := 1.5
	var seconds := elapsed
	var shift := 0.0
	if animation == "move" and show_translation:
		var cycle := float(record.gait.cycle_distance_px)*scale_value
		shift = fposmod(elapsed,2.0)*cycle-cycle
	var region: Rect2 = selector.frame_rect("armored_titan",animation,seconds)
	var anchor := Vector2(record.anchor_px[0],record.anchor_px[1])
	for side in [0,1]:
		var facing := 1.0 if side == 0 else -1.0
		var origin := Vector2(205.0+390.0*side+shift*facing,480.0)
		draw_set_transform(origin,0.0,Vector2(scale_value*facing,scale_value))
		draw_texture_rect_region(atlas,Rect2(-anchor,region.size),region)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
