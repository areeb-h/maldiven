extends Node3D
## Photo studio for the key-art showcase: builds the real station once (sockets,
## VFX, ambient effects), then gives each shot a clean "set" to dress with crew,
## props and extra lights, a cinematic camera with depth of field, and a capture.
##
## Shots live in the set scripts (set_*.gd), which extend this one; the first
## set builds the world with setup() and the others borrow it with share_world().
## The trailer (tools/trailer/) reuses the same rig. Every helper here is
## deterministic for a given seed, so re-running a shot reproduces the frame.

## Player suit colours, in lobby order.
const COLORS := {
	"red": Color("ff5a5a"), "blue": Color("4da3ff"), "yellow": Color("ffd23f"), "green": Color("53d769"),
	"purple": Color("c77dff"), "orange": Color("ff9f40"), "teal": Color("3fe0d0"), "white": Color("f2f2f2"),
}
## Fixed simulation step used to pose characters (independent of render speed).
const STEP := 1.0 / 60.0
## Light colours shared by the shots.
const WARM := Color(1.0, 0.86, 0.68)
const COOL := Color(0.55, 0.75, 1.0)
const CYAN := Color(0.3, 0.9, 1.0)
## Floating product stage, high above the station so only stars and the gas
## giant sit behind it (camera looking north).
const STAGE := Vector3(30.0, 60.0, 40.0)

var station: ArtStationFX
var vfx: Vfx
var sockets: Dictionary = {}  # socket id -> SocketVisual
var camera: Camera3D
var attrs: CameraAttributesPractical
## Everything a shot adds goes under this node; it is freed before the next shot.
var set_root: Node3D
## The crew stand under a CharacterBody3D, as in gameplay (CrewMember), so the
## VFX treat items they hold as carried rather than lying on the floor.
var cast_root: CharacterBody3D
var _models: Array[CrewModel] = []
var _extras: Array[Node] = []  # shot nodes parented outside set_root (e.g. into sockets)
var _env_defaults: Dictionary = {}
var _focus := Vector3.ZERO
## Headless layout check (showcase --check): run the shots, report camera
## problems, save nothing.
var check_only := false


# --- world --------------------------------------------------------------------------

## Builds the station, its sockets and the VFX layer. Call once, then await a frame.
func setup() -> void:
	name = "Studio"
	station = StationBuilder.build(self) as ArtStationFX
	vfx = Vfx.new()
	vfx.name = "Vfx"
	add_child(vfx)
	vfx.ambient_station(station)
	for socket_id in StationLayout.SOCKETS:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		var socket: Node3D = Props.make_socket(spec.kind)
		socket.name = "Socket_" + socket_id
		socket.position = StationLayout.to_world(spec.pos)
		socket.rotation.y = spec.facing
		add_child(socket)
		sockets[socket_id] = socket
	camera = Camera3D.new()
	camera.name = "KeyArtCamera"
	camera.far = 2500.0
	camera.near = 0.05
	add_child(camera)
	camera.current = true
	attrs = CameraAttributesPractical.new()
	camera.attributes = attrs
	var env := station.env
	for key in ["glow_strength", "glow_bloom", "fog_height_density", "adjustment_contrast", "adjustment_saturation", "ssao_enabled"]:
		_env_defaults[key] = env.get(key)


## Borrows the world another set node built with setup().
func share_world(from: Node3D) -> void:
	station = from.station
	vfx = from.vfx
	sockets = from.sockets
	camera = from.camera
	attrs = from.attrs
	_env_defaults = from._env_defaults


## Frees whatever the last shot of this set left behind.
func end_set() -> void:
	if set_root != null and is_instance_valid(set_root):
		set_root.free()
	for node in _extras:
		if is_instance_valid(node):
			node.free()
	_extras.clear()
	_models.clear()


## Clears the previous set and returns the station to a neutral baseline.
## `power` is "emergency", "restored" or "blackout"; `seed_value` fixes randomness.
func begin_shot(power: String, seed_value: int) -> void:
	seed(seed_value)
	end_set()
	set_root = Node3D.new()
	set_root.name = "Set"
	add_child(set_root)
	cast_root = CharacterBody3D.new()
	cast_root.name = "Cast"
	cast_root.collision_layer = 0
	cast_root.collision_mask = 0
	set_root.add_child(cast_root)
	station.set_state(power, 0.0)
	station.set_airlock_state("idle")
	for key in _env_defaults:
		station.env.set(key, _env_defaults[key])
	for socket_id in sockets:
		var spec: Dictionary = StationLayout.SOCKETS[socket_id]
		(sockets[socket_id] as SocketVisual).set_state(false, spec.kind in ["vault", "armory"], false)
	attrs.exposure_multiplier = 1.0
	attrs.dof_blur_far_enabled = false
	attrs.dof_blur_near_enabled = false


# --- crew ---------------------------------------------------------------------------

## Adds a crew member standing at `pos`, facing yaw `yaw_deg` (0 = facing +Z).
func crew(color_key: String, pos: Vector3, yaw_deg: float, expression := "neutral", variant := 0, number := 0) -> CrewModel:
	var m := CrewModel.build(COLORS[color_key], variant, number)
	m.position = pos
	m.rotation.y = deg_to_rad(yaw_deg)
	cast_root.add_child(m)
	m.set_expression(expression)
	_models.append(m)
	return m


## Turns `m` (in place) so it faces the world point `target` on the floor plane.
func face(m: Node3D, target: Vector3) -> void:
	var d := target - m.position
	m.rotation.y = atan2(d.x, d.z)


## Steps the locomotion rig at a fixed rate for `seconds` (idle when speed is 0).
## Keep idle holds under ~5 s so the random fidgets never start on their own.
func pose(m: CrewModel, seconds: float, speed := 0.0, carrying := false, stunned := false) -> void:
	for i in int(seconds / STEP):
		m.set_motion(speed, true, carrying, stunned, STEP)


## Runs `m` up to `speed`, then stops on the stride `phase` (0..1 gait cycle).
func pose_stride(m: CrewModel, speed: float, phase: float, carrying := false) -> void:
	pose(m, 1.6, speed, carrying)
	var guard := 0
	while guard < 240 and absf(wrapf(float(m.get("_phase")) - phase, -0.5, 0.5)) > 0.012:
		m.set_motion(speed, true, carrying, false, STEP * 0.25)
		guard += 1


## Steps a one-shot overlay (shove / hit) forward until `t` seconds have elapsed.
func pose_overlay(m: CrewModel, t: float, speed := 0.0, carrying := false) -> void:
	for i in int(t / STEP):
		m.set_motion(speed, true, carrying, false, STEP)


## Pose override (no CrewModel API for it yet): arms raised in surrender with
## open gloves. Bones are in chest space; the arm rests along -Y and its forearm
## hinges on local X, so the upper arm is turned to make the elbow bend point up.
## Call after the last pose()/set_motion step.
func hands_up(m: CrewModel) -> void:
	for side in 2:
		var s := 1.0 if side == 0 else -1.0
		var up := CrewBody.L_ARM if side == 0 else CrewBody.R_ARM
		var raise := Basis(Vector3(0, 0, -s), Vector3(-s, 0, 0), Vector3(0, 1, 0))
		m.bones[up].basis = Basis(Vector3.UP, -s * 0.45) * Basis(Vector3.BACK, s * 0.32) * raise
		m.bones[up + 1].basis = Basis(Vector3.RIGHT, -1.75)
		m.bones[up + 2].basis = Basis(Vector3.RIGHT, -0.15)
	m._upload()
	glove(m, 0, "open")
	glove(m, 1, "open")


## Pose override: one arm raised high (a wave or a call to the crew), glove
## waving. side 0 = left, 1 = right. Call after the last pose step.
func raise_arm(m: CrewModel, side: int) -> void:
	var s := 1.0 if side == 0 else -1.0
	var up := CrewBody.L_ARM if side == 0 else CrewBody.R_ARM
	var raise := Basis(Vector3(0, 0, -s), Vector3(-s, 0, 0), Vector3(0, 1, 0))
	m.bones[up].basis = Basis(Vector3.UP, -s * 0.2) * Basis(Vector3.BACK, s * 0.75) * raise
	m.bones[up + 1].basis = Basis(Vector3.RIGHT, -0.7)
	m.bones[up + 2].basis = Basis.IDENTITY
	m._upload()
	glove(m, side, "wave")


## Pose override: snaps one glove (0 left, 1 right) to a CrewHand pose such as
## "open", "point", "thumbs_up", "wave" or "fist". Call after the last pose step.
func glove(m: CrewModel, side: int, pose_name: String) -> void:
	var hand: CrewHand = m.hands[side]
	hand.set_pose(pose_name, 0.0)
	hand.set_motion(0.0, 0.016)


## Pose override: turns the head (on top of the current pose) by yaw/pitch degrees.
## Positive yaw looks to the character's left, positive pitch looks down.
func turn_head(m: CrewModel, yaw_deg: float, pitch_deg := 0.0) -> void:
	var head := m.bones[CrewBody.HEAD]
	head.basis = head.basis * Basis.from_euler(Vector3(deg_to_rad(pitch_deg), deg_to_rad(yaw_deg), 0.0))
	m._upload()


## Gives `m` a hand-held flashlight like gameplay's (Props.make_flashlight) aimed at
## `target`, lights the helmet lamp, and adds a faint additive beam cone so the
## light reads in the dark (the Mobile renderer has no volumetric fog).
func flashlight(m: CrewModel, target: Vector3, beam_energy := 0.22, shadows := true) -> SpotLight3D:
	m.set_flashlight_on(true)
	var light := Props.make_flashlight()
	set_root.add_child(light)
	var origin := m.global_transform * Vector3(-0.08, 1.38, 0.32)
	light.look_at_from_position(origin, target, Vector3.UP)
	light.shadow_enabled = shadows
	light.light_energy = 6.0
	var length := minf(origin.distance_to(target) * 1.25, 9.0)
	var cone := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = tan(deg_to_rad(light.spot_angle * 0.85)) * length
	mesh.height = length
	mesh.radial_segments = 32
	mesh.rings = 8
	mesh.cap_top = false
	mesh.cap_bottom = false
	cone.mesh = mesh
	cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = _beam_shader()
	mat.set_shader_parameter("tint", Vector3(light.light_color.r, light.light_color.g, light.light_color.b))
	mat.set_shader_parameter("energy", beam_energy)
	mat.set_shader_parameter("height", length)
	cone.material_override = mat
	light.add_child(cone)
	# Cylinder axis is +Y; the light shines along -Z.
	cone.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0, 0, -length * 0.5))
	return light


static var _beam: Shader


static func _beam_shader() -> Shader:
	if _beam == null:
		_beam = Shader.new()
		_beam.code = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec3 tint = vec3(1.0);
uniform float energy = 0.2;
uniform float height = 6.0;
varying float along;
void vertex() {
	along = clamp(0.5 - VERTEX.y / height, 0.0, 1.0);
}
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float fade = smoothstep(0.0, 0.12, along) * pow(1.0 - along, 1.6);
	ALBEDO = tint * energy * pow(facing, 2.5) * fade;
}
"""
	return _beam


## Moves `node` along a ballistic arc from `from` to `to` over `frames` rendered
## frames (spinning it as it goes), so attached trails draw a real path.
func fly(node: Node3D, from: Vector3, to: Vector3, arc: float, frames: int, spin := Vector3(4.0, 6.0, 2.0)) -> void:
	for i in frames + 1:
		var k := float(i) / float(frames)
		node.position = from.lerp(to, k) + Vector3(0, arc * 4.0 * k * (1.0 - k), 0)
		node.rotation = spin * k
		await get_tree().process_frame


## Keeps the recoil pose of a play_hit() but drops its red "you were shot" rim
## flash (for knock-backs that are not gunfire). Call after the last pose step.
func clear_hit_flash(m: CrewModel) -> void:
	m.set("_hit_t", -1.0)


## Lets faces, lamps and hit flashes settle, then freezes every model so the
## frame holds still while the slow software renderer catches up.
func freeze_crew() -> void:
	for m in _models:
		if not is_instance_valid(m):
			continue
		m.set("_blink_timer", 1000.0)
		m.set("_saccade_timer", 1000.0)
		m.set("_saccade", Vector2.ZERO)
		for i in 6:
			m._process(0.05)
		m.process_mode = Node.PROCESS_MODE_DISABLED


## Gives `m` an item the way gameplay does: cells and cores ride on carry_anchor,
## the gun sits in the right glove at hand_anchor. Also tells the model what it
## holds, which picks the glove grips, so call it BEFORE posing.
func hold(m: CrewModel, kind: String) -> Node3D:
	var node := Props.make_item(kind)
	(m.hand_anchor if kind == "gun" else m.carry_anchor).add_child(node)
	m.set_held_item(kind)
	if kind == "core" or kind == "cell":
		vfx.attach_item_fx(node, kind)
	return node


## Seats an item in a socket exactly as gameplay does (so its fx know it is
## socketed, not lying on the floor). Removed again by the next begin_shot().
func seat_item(socket_id: String, kind: String) -> Node3D:
	var socket := sockets[socket_id] as SocketVisual
	var node := Props.make_item(kind)
	socket.add_child(node)
	node.transform = socket.get_seat_transform()
	_extras.append(node)
	if kind == "core" or kind == "cell":
		vfx.attach_item_fx(node, kind)
	return node


## World-space muzzle of a gun item (barrel along its +Z): the centre of the
## front face of its mesh bounds, and the barrel direction.
func muzzle(gun: Node3D) -> Transform3D:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in gun.find_children("*", "MeshInstance3D", true, false):
		var local := gun.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		box = local if first else box.merge(local)
		first = false
	var tip := Vector3(box.get_center().x, box.position.y + box.size.y * 0.62, box.end.z)
	var forward := (gun.global_transform.basis * Vector3.BACK).normalized()
	return Transform3D(Basis.looking_at(forward), gun.global_transform * tip)


## Places a loose item in the world. Cells and cores get their glow fx.
func place_item(kind: String, xf: Transform3D, with_fx := true) -> Node3D:
	var node := Props.make_item(kind)
	node.transform = xf
	set_root.add_child(node)
	if with_fx and (kind == "core" or kind == "cell"):
		vfx.attach_item_fx(node, kind)
	return node


# --- product stage --------------------------------------------------------------------

## Builds the floating product stage (a dark glossy disc with a glowing rim) at
## STAGE + offset and returns its top centre. Pair it with begin_shot("blackout")
## and stage_lighting() so only the shot's own lights shape the subject.
func stage(radius := 1.4, offset := Vector3.ZERO, rim := CYAN) -> Vector3:
	var top := STAGE + offset
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 0.92
	mesh.height = 0.16
	mesh.radial_segments = 64
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.055, 0.065)
	mat.metallic = 0.6
	mat.roughness = 0.38
	disc.material_override = mat
	disc.position = top - Vector3(0, 0.08, 0)
	set_root.add_child(disc)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.02
	torus.outer_radius = radius + 0.02
	torus.rings = 96
	ring.mesh = torus
	var glow := StandardMaterial3D.new()
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow.albedo_color = rim * 1.6
	ring.material_override = glow
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.position = top + Vector3(0, -0.01, 0)
	set_root.add_child(ring)
	return top


## Night-studio look for the stage: no fog, sky reflections back on for the
## glossy surfaces, a touch of ambient.
func stage_lighting() -> void:
	station.env.fog_density = 0.0
	station.env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	station.env.ambient_light_energy = 0.25


## A crew-free item for product shots, parented so its fx treat it as held (no
## floor beacon), with its glow fx.
func stage_item(kind: String, xf: Transform3D) -> Node3D:
	var node := Props.make_item(kind)
	cast_root.add_child(node)
	node.global_transform = xf
	if kind == "core" or kind == "cell":
		vfx.attach_item_fx(node, kind)
	return node


# --- lights -------------------------------------------------------------------------

## Spot light aimed from `pos` at `target`. Rims and fills keep shadows off.
## `specular` < 1 keeps a frontal key from washing out the glossy visor.
func spot(pos: Vector3, target: Vector3, color: Color, energy: float, angle := 30.0, reach := 12.0, shadows := false, specular := 1.0) -> SpotLight3D:
	var l := SpotLight3D.new()
	set_root.add_child(l)
	l.look_at_from_position(pos, target, Vector3.UP if absf((target - pos).normalized().y) < 0.98 else Vector3.FORWARD)
	l.light_color = color
	l.light_energy = energy
	l.spot_angle = angle
	l.spot_angle_attenuation = 0.8
	l.spot_range = reach
	l.spot_attenuation = 1.0
	l.shadow_enabled = shadows
	l.shadow_blur = 1.5
	l.light_specular = specular
	return l


func omni(pos: Vector3, color: Color, energy: float, reach := 6.0, shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	set_root.add_child(l)
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = reach
	l.omni_attenuation = 1.2
	l.shadow_enabled = shadows
	return l


## Classic three-point rig around a subject point: warm-ish key, coloured rim
## from behind, soft fill. Offsets are relative to the camera's view of `subject`.
func three_point(subject: Vector3, cam_pos: Vector3, key_color: Color, key_energy: float, rim_color: Color, rim_energy: float, fill_energy := 0.6, key_side := 1.0) -> void:
	var to_cam := Vector3(cam_pos.x - subject.x, 0.0, cam_pos.z - subject.z).normalized()
	var side := to_cam.cross(Vector3.UP).normalized() * key_side
	spot(subject + to_cam * 2.6 + side * 2.4 + Vector3(0, 1.6, 0), subject, key_color, key_energy, 32.0, 9.0, true)
	spot(subject - to_cam * 2.4 - side * 1.6 + Vector3(0, 1.4, 0), subject + Vector3(0, 0.2, 0), rim_color, rim_energy, 34.0, 8.0)
	if fill_energy > 0.0:
		spot(subject + to_cam * 3.0 - side * 2.8 + Vector3(0, 0.4, 0), subject, Color(0.75, 0.85, 1.0), fill_energy, 40.0, 9.0)


# --- camera -------------------------------------------------------------------------

## Points the camera from `pos` at `target`. `focus` is the sharp point; `depth`
## is the in-focus slab (metres) around it; `blur` 0..1 sets the bokeh strength.
## `roll_deg` tilts the horizon (Dutch angle) when a shot calls for it.
func frame(pos: Vector3, target: Vector3, fov: float, focus: Vector3, depth := 1.2, blur := 0.12, near_blur := true, roll_deg := 0.0) -> void:
	camera.fov = fov
	camera.look_at_from_position(pos, target, Vector3.UP)
	if roll_deg != 0.0:
		camera.rotate_object_local(Vector3.FORWARD, deg_to_rad(roll_deg))
	_focus = focus
	var d := pos.distance_to(focus)
	attrs.dof_blur_amount = blur
	attrs.dof_blur_far_enabled = blur > 0.0
	attrs.dof_blur_far_distance = d + depth * 0.5
	attrs.dof_blur_far_transition = maxf(d * 0.9, 1.0)
	attrs.dof_blur_near_enabled = near_blur and blur > 0.0 and d > depth
	attrs.dof_blur_near_distance = maxf(d - depth * 0.5, 0.1)
	attrs.dof_blur_near_transition = maxf((d - depth * 0.5) * 0.4, 0.05)


# --- timing and capture -------------------------------------------------------------

func wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## Composition guard: warns when the camera sits inside station geometry or a
## collider blocks the line to the focus point (station props move between
## builds, so a framing that was clear can become blocked).
func check_view(label: String) -> void:
	var space := get_world_3d().direct_space_state
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.2
	probe.shape = sphere
	probe.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	probe.collision_mask = 1 | 16
	for hit in space.intersect_shape(probe, 4):
		push_warning("showcase: %s: camera inside %s" % [label, _collider_name(hit.collider)])
	var ray := PhysicsRayQueryParameters3D.create(camera.global_position, _focus, 1 | 16)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.position.distance_to(_focus) > 0.6:
		push_warning("showcase: %s: view to focus blocked by %s at %s" % [label, _collider_name(hit.collider), hit.position])


static func _collider_name(node: Object) -> String:
	var n := node as Node
	return "%s/%s" % [n.get_parent().name, n.name] if n != null and n.get_parent() != null else str(node)


## Renders the current frame and saves it as a PNG at `path`.
func snap(path: String) -> Error:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	return image.save_png(path)


## Freezes the crew, lets `warm` frames render (shader warm-up, probes, particles)
## and saves `<out>/<file>`. Prints the saved path so callers can collect it.
func capture(out: String, file: String, warm := 4) -> Error:
	freeze_crew()
	await wait(1 if check_only else warm)
	check_view(file)
	if check_only:
		print("showcase: checked ", file)
		return OK
	var path := out.path_join(file)
	var err := await snap(path)
	if err == OK:
		print("showcase: saved ", path)
	return err
