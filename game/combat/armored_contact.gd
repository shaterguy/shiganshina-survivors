extends RefCounted
# One local, pure narrow phase for the final actor's separate shoulder circle.
# The ordinary body keeps its existing conservative box-expanded sweep.
static func trace(origin: Vector2, delta: Vector2, radius: float, shapes: Array, bounds: Variant = null) -> Dictionary:
	var best := {"fraction":1.0,"contact":{}}
	if bounds is Rect2:
		var legal: Rect2 = bounds.grow(-radius)
		for axis in 2:
			if delta[axis] == 0: continue
			var edge: float = legal.end[axis] if delta[axis] > 0 else legal.position[axis]
			var f: float = (edge-origin[axis])/delta[axis]
			if f < 0 or f > 1: continue
			var center := origin+delta*f
			var normal := Vector2.ZERO
			normal[axis] = -1.0 if delta[axis] > 0 else 1.0
			best = _choose(best,f,{"shape_id":"bounds:%d:%d"%[axis,1 if delta[axis]>0 else 0],"prop_id":"","shape":"shoulder_circle","point":center-normal*radius,"center":center,"normal":normal})
	for shape in shapes:
		var box: Rect2 = shape.rect
		var hit := circle_rect(origin,delta,radius,box)
		if hit.is_empty(): continue
		hit.shape_id = str(shape.id)
		hit.prop_id = str(shape.get("prop_id",""))
		hit.shape = "shoulder_circle"
		best = _choose(best,float(hit.fraction),hit)
	return best
static func clear(origin: Vector2, end: Vector2, radius: float, shapes: Array, bounds: Variant = null) -> bool:
	if bounds is Rect2:
		var legal: Rect2 = bounds.grow(-radius)
		for point in [origin,end]:
			if point.x < legal.position.x or point.y < legal.position.y or point.x > legal.end.x or point.y > legal.end.y: return false
	for shape in shapes:
		var box: Rect2 = shape.rect
		if origin.distance_squared_to(origin.clamp(box.position,box.end)) < radius*radius: return false
		if end.distance_squared_to(end.clamp(box.position,box.end)) < radius*radius: return false
		var hit := circle_rect(origin,end-origin,radius,box)
		if not hit.is_empty() and float(hit.fraction) < 1.0: return false
	return true
static func circle_rect(origin: Vector2, delta: Vector2, radius: float, box: Rect2) -> Dictionary:
	var best := {"fraction":1.0,"contact":{}}
	var nearest := origin.clamp(box.position,box.end)
	var separation := origin-nearest
	if separation.length_squared() < radius*radius:
		return {"fraction":0.0,"point":nearest,"center":origin,"normal":separation.normalized()}
	# Face strips, excluding their rounded corners.
	for axis in 2:
		if delta[axis] == 0: continue
		var positive: bool = delta[axis] > 0
		var edge: float = box.position[axis]-radius if positive else box.end[axis]+radius
		var f: float = (edge-origin[axis])/delta[axis]
		if f < 0 or f > 1: continue
		var center := origin+delta*f
		var other := 1-axis
		if center[other] < box.position[other] or center[other] > box.end[other]: continue
		var normal := Vector2.ZERO
		normal[axis] = -1.0 if positive else 1.0
		best = _choose(best,f,{"fraction":f,"point":center-normal*radius,"center":center,"normal":normal})
	var a := float(delta.length_squared())
	if a > 0:
		for corner_index in 4:
			var high_x: bool = corner_index % 2 == 1
			var high_y: bool = corner_index >= 2
			var corner := Vector2(box.end.x if high_x else box.position.x,box.end.y if high_y else box.position.y)
			var relative := origin-corner
			var b := 2.0*float(relative.dot(delta))
			var c := float(relative.length_squared())-radius*radius
			var discriminant := b*b-4.0*a*c
			if discriminant < 0: continue
			var f := (-b-sqrt(discriminant))/(2.0*a)
			if f < 0 or f > 1: continue
			var center := origin+delta*f
			if (center.x < corner.x if high_x else center.x > corner.x) or (center.y < corner.y if high_y else center.y > corner.y): continue
			var normal := (center-corner).normalized()
			if delta.dot(normal) >= 0: continue
			best = _choose(best,f,{"fraction":f,"point":corner,"center":center,"normal":normal})
	return best.contact
static func _choose(best: Dictionary, fraction: float, contact: Dictionary) -> Dictionary:
	if fraction > float(best.fraction): return best
	if fraction == float(best.fraction) and not best.contact.is_empty() and str(contact.get("shape_id","")) >= str(best.contact.get("shape_id","")): return best
	contact.fraction = fraction
	return {"fraction":fraction,"contact":contact}
static func combine(root: Vector2, delta: Vector2, body: Dictionary, shoulder: Dictionary) -> Dictionary:
	var body_fraction := 1.0 if delta.is_zero_approx() or (float(body.get("fraction",1.0)) == 1.0 and body.position.distance_to(root+delta) <= 0.00001) else clampf((body.position-root).dot(delta)/delta.length_squared(),0.0,1.0)
	body_fraction = minf(body_fraction,float(body.get("fraction",1.0)))
	# Deliberately no near-tie epsilon: an earlier body stop is not a witness.
	var reached: bool = not shoulder.contact.is_empty() and float(shoulder.fraction) <= body_fraction
	var fraction := minf(body_fraction,float(shoulder.fraction))
	return {"ok":true,"position":root+delta*fraction,"fraction":fraction,"contact":shoulder.contact if reached else {},"body_fraction":body_fraction,"shoulder_fraction":float(shoulder.fraction),"stopped":fraction < 1.0 or reached}
