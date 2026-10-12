extends Control
## Authored-only QA fixture. Native execution is NOT authorized by its presence.
## Stored golden rows are pose-command fixtures, never a real Core contact trace.
const RASTER = preload("res://game/presentation/armored/armored_raster.gd")
const PACKET = preload("res://game/presentation/armored/armored_pose_packet.gd")
class TickMarker extends Node2D:
	var tick = 0
	func _draw() -> void:
		for bit in range(31):
			draw_rect(Rect2(2 + bit * 3, 2, 2, 4), Color.WHITE if tick & (1 << bit) else Color(1, 0, 1, 1))
var _raster
var _registration: Dictionary
var _rows: Array
var _index = 0
var _marker: TickMarker
var _status: Label
var _views: Array[Sprite2D] = []
func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_registration = JSON.parse_string(FileAccess.get_file_as_string("res://assets/art/rig/armored_runtime_v1/registration.json"))
	_rows = JSON.parse_string(FileAccess.get_file_as_string("res://tests/armored_raster/golden_rows.json")).rows
	_raster = RASTER.new()
	add_child(_raster)
	_status = Label.new()
	_status.position = Vector2(8, 8)
	add_child(_status)
	var result: Dictionary = _raster.configure(_registration)
	if not result.ok:
		_status.text = "QA ERROR: " + result.reason
		return
	_marker = TickMarker.new()
	_raster.get_child(0).add_child(_marker)
	var output_material = CanvasItemMaterial.new()
	output_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	output_material.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	for i in range(3):
		var sprite = Sprite2D.new()
		sprite.texture = _raster.get_raster_texture()
		sprite.material = output_material
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		sprite.scale = Vector2.ONE * [1.0, 1.5, 2.0][i]
		sprite.position = Vector2(8 + i * 310, 80)
		add_child(sprite)
		_views.append(sprite)
	_present()
func _present() -> void:
	var fixture: Dictionary = _rows[_index]
	var packet: Dictionary = PACKET.new().compile_pose(fixture.row, _registration)
	if not _raster.present_packet(packet):
		_status.text = "QA ERROR: " + _raster.last_error
		return
	_marker.tick = packet.pose_tick
	_marker.queue_redraw()
	# QA marker itself changed. This explicit QA update is separate from the
	# production owner's once-per-changed-draw scheduling.
	_raster.get_child(0).render_target_update_mode = SubViewport.UPDATE_ONCE
	_status.text = "STORED GOLDEN ONLY / HOLD / native comparison pending\n%s | outer expected tick %d | requested generation %d\nSpace: next | M: mirror native result about x144. Inner 31-bit marker must match outer tick." % [fixture.fixture_id, packet.pose_tick, _raster.packet_status().generation]
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo or _marker == null: return
	if event.keycode == KEY_SPACE:
		_index = (_index + 1) % _rows.size()
		_present()
	if event.keycode == KEY_M:
		for sprite in _views: sprite.flip_h = not sprite.flip_h
