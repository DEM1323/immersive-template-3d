extends Interactable

# This is an example of how to create an interactable object

# This is not intended to be directly edited, please create a new 
# interactable object using this as referance or a guide

# Please see "interactable.gd" to view the parent class and usable variables

# *ADVANCED USERS* You can add your own interaction signals in "interaction_bus.gd" and "mouse.gd"

# Selects the mesh that will have it's color changed 
# depending on if the mouse/touch is hovering over it or not
@onready var mesh := $MeshInstance3D
@onready var parent := $"."

# Runs continuosly, use delta time instead of frame time
func _process(delta):
	# Please see interactable.gd to view the parent class
	super(delta)
	
	# Add any unique behavior code below the "super()" lines
	if is_clicked:
		parent.global_position = ray_pos[0] + (ray_pos[1] * 3)

# Runs once when the mouse leaves this collider
func _on_ray_exit(collider):
	if collider == self:
		super(collider)
		
		# Example code to change color of mesh on mouse/touch exit
		_set_color(Color.RED)

# Runs once when the mouse enters this collider
func _on_ray_enter(collider):
	if collider == self:
		super(collider)
		
		# Example code to change color of mesh on mouse/touch enter
		_set_color(Color.GREEN)

# Helper function to set color of mesh, unrelated to underlying interaction code
func _set_color(color: Color):
	var mat = mesh.get_surface_override_material(0)
	
	if mat == null:
		mat = StandardMaterial3D.new()
		mesh.set_surface_override_material(0, mat)
	
	mat.albedo_color = color
