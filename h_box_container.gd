extends HBoxContainer

func _input(event):
	if event is InputEventMouseMotion:
		var mouse_pos = event.position
		
		for container in get_children():
			var rect = container.get_global_rect()
			if rect.has_point(mouse_pos):
				handle_mouse_in_view(container, mouse_pos)
				break

func handle_mouse_in_view(container, global_mouse_pos):
	var local_pos = global_mouse_pos - container.get_global_position()
	
	var subviewport = container.get_viewport()
	var camera = subviewport.get_camera_3d()
	
	project_to_3d(camera, local_pos, subviewport.size)

func project_to_3d(camera: Camera3D, local_pos: Vector2, viewport_size: Vector2):
	# Normalize mouse position into viewport space
	var screen_pos = local_pos

	var ray_origin = camera.project_ray_origin(screen_pos)
	var ray_dir = camera.project_ray_normal(screen_pos)

	# Cast into world
	var space_state = camera.get_world_3d().direct_space_state
	var result = space_state.intersect_ray(
		ray_origin
	)

	if result:
		print("Hit position: ", result.position)
