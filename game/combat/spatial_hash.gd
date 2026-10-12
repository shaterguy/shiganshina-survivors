class_name CombatSpatialHash
extends RefCounted
# Transient broad phase. DTOs retain only JSON-safe positions and IDs.
var cell_size: float = 64.0
var cells: Dictionary = {}
func rebuild(records: Array) -> void:
	cells.clear()
	for index in records.size():
		var position: Array = records[index].position
		var key := _key(float(position[0]), float(position[1]))
		if not cells.has(key): cells[key] = []
		cells[key].append(index)
func query(position: Vector2, radius: float) -> Array[int]:
	var result: Array[int] = []
	var minimum := Vector2i(floor((position.x-radius)/cell_size),floor((position.y-radius)/cell_size))
	var maximum := Vector2i(floor((position.x+radius)/cell_size),floor((position.y+radius)/cell_size))
	for x in range(minimum.x,maximum.x+1):
		for y in range(minimum.y,maximum.y+1):
			for index in cells.get("%d:%d"%[x,y],[]): result.append(index)
	result.sort()
	return result
func _key(x: float, y: float) -> String:
	return "%d:%d" % [int(floor(x/cell_size)),int(floor(y/cell_size))]
