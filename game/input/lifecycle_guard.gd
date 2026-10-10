extends RefCounted
# Android reports physical screen pixels; UI consumes logical viewport units.
func map_safe_area(viewport_size: Vector2i, window_size: Vector2i, safe_screen_rect: Rect2i, window_position: Vector2i) -> Rect2i:
	var full := Rect2i(Vector2i.ZERO,viewport_size)
	if viewport_size.x <= 0 or viewport_size.y <= 0 or window_size.x <= 0 or window_size.y <= 0 or not safe_screen_rect.has_area(): return full
	var clipped := safe_screen_rect.intersection(Rect2i(window_position,window_size))
	if not clipped.has_area(): return full
	var scale := Vector2(viewport_size)/Vector2(window_size)
	var low := Vector2(clipped.position-window_position)*scale
	var high := Vector2(clipped.end-window_position)*scale
	# Round inward so a fractional notch edge never overlaps a tappable control.
	var start := Vector2i(ceili(low.x),ceili(low.y))
	var finish := Vector2i(floori(high.x),floori(high.y))
	return Rect2i(start,finish-start).intersection(full)
