extends SceneTree

var floor_body: StaticBody3D
var pusher: AnimatableBody3D
var box: RigidBody3D
var t := 0

func _initialize() -> void:
	var root3d := Node3D.new()
	root.add_child(root3d)
	floor_body = StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(40, 1, 40)
	fs.shape = bs
	fs.position.y = -0.5
	floor_body.add_child(fs)
	root3d.add_child(floor_body)
	pusher = AnimatableBody3D.new()
	var ps := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.8
	ps.shape = cap
	ps.position.y = 0.9
	pusher.add_child(ps)
	pusher.collision_layer = 32
	pusher.collision_mask = 0
	pusher.position = Vector3(-2, 0, 0)
	root3d.add_child(pusher)
	box = RigidBody3D.new()
	var bxs := CollisionShape3D.new()
	var bb := BoxShape3D.new()
	bb.size = Vector3(0.8, 0.7, 0.8)
	bxs.shape = bb
	bxs.position.y = 0.35
	box.add_child(bxs)
	box.mass = 16
	box.collision_layer = 16
	box.collision_mask = 1 | 32 | 16
	box.position = Vector3(0, 0.0, 0)
	root3d.add_child(box)
	print("sync_to_physics=", pusher.sync_to_physics)
	physics_frame.connect(_step)

func _step() -> void:
	t += 1
	if t < 200:
		pusher.global_position.x += 3.4 / 60.0
	if t % 20 == 0:
		print(t, " pusher=", snapped(pusher.global_position.x, 0.01), " box=", box.global_position.snapped(Vector3.ONE*0.01), " v=", box.linear_velocity.snapped(Vector3.ONE*0.01), " sleep=", box.sleeping)
	if t > 320:
		quit()
