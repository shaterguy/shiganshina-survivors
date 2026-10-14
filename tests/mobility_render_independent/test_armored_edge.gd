extends RefCounted
const View = preload("res://game/presentation/world_view.gd")
const Armored = preload("res://game/presentation/armored/armored_raster.gd")
const Fixture = preload("res://tests/armored_raster/alpha_fixture.gd")
const Reference = preload("res://tests/mobility_render_independent/test_adversarial_pixels.gd")
func run(t):
	var view := View.new()
	var sample := Image.create(1,1,false,Image.FORMAT_RGBA8)
	sample.fill(Color.WHITE)
	view._assets = {"garrison_01":{"cell_w":1,"cell_h":1,"columns":1},"other":{"cell_w":1,"cell_h":1,"columns":1}}
	view._raster_images = {"garrison_01":sample,"other":sample}
	view._player_outline_texture(Rect2(0,0,1,1))
	var owner := Armored.new()
	t.root.add_child(owner)
	var fixture := Fixture.new()
	var registration := fixture.registration()
	t.check(owner.configure(registration).ok,"edge regression uses validated imported armored registration")
	var packet := fixture.packet(registration)
	for command in packet.commands:
		command.transform.origin += Vector2(.2,.2)
		command.source_transform.origin += Vector2(.2,.2)
		command.bounds.position += Vector2(.2,.2)
	packet.bounds.position += Vector2(.2,.2)
	packet.commands[0].modulate = Color.WHITE
	t.check(owner.present_packet(packet),"fractional edge packet accepted by full armored validator")
	view._armored_raster = owner
	view._armored_display = {"supported":true,"root_position":Vector2(123.4,259.4),"flip":false,"display_scale":1.0}
	view._city_draw_data = {"actor":{"x":{"armored_raster":true}}}
	var player := {"asset_id":"garrison_01","pose":"idle","seconds":0.0,"render_bounds":Rect2(0,0,1,1),"flip":false}
	var other := {"id":"actor:x","source_id":"x","asset_id":"other","pose":"idle","render_bounds":view._armored_world_transform()*owner.local_bounds()}
	t.check(not other.render_bounds.has_point(Vector2(.5,.5)),"regression pixel lies outside continuous armored bounds")
	t.check(view._armored_opaque(Vector2(.5,.5)),"same pixel maps to opaque native armored texel")
	t.check(Reference.new()._reference(view,player,other),"baseline overlap includes opaque sampled edge")
	t.check(view._city_rasters_overlap(player,other),"optimized overlap retains opaque sampled armored edge")
	view._armored_raster = null
	owner.free()
	view.free()
