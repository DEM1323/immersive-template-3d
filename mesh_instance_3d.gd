extends MeshInstance3D

var max_timer := 1.5
var timer := 0.001
var dir = false
var pos1
var pos2

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pos1 = global_transform.origin
	pos2 = pos1
	pos2.x = (pos1.x - 25)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	
	timer += 0.01
	
	if timer >= max_timer:
		dir = !dir
		timer = 0
	
	if dir:
		global_transform.origin.x = lerp(global_position.x, pos1.x, 0.01)
	else:
		global_transform.origin.x = lerp(global_position.x, pos2.x, 0.01)
	
	var rotate_speed = 1
	
	rotate_x(rotate_speed * delta)
	rotate_y(rotate_speed * delta)
	rotate_z(rotate_speed * delta)
