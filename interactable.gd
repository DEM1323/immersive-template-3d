extends Node
class_name Interactable

# DO NOT ADD INTERACTABLE BEHAVIOR HERE
# THIS IS A SUPER CLASS MEANT TO BE INHERITED BY ALL INTERACTABLE OBJECTS
# *ADVANCE USERS* EDIT WITH CARE

var hover_time: float
var is_hovering: bool = false
var is_clicked: bool = false
var ray_pos: Array
var col_identifier 

func _ready():
	# Connect signal bus to interactable
	InteractionBus.ray_hover.connect(_on_ray_hover)
	InteractionBus.ray_exit.connect(_on_ray_exit)
	InteractionBus.ray_enter.connect(_on_ray_enter)
	InteractionBus.ray_click.connect(_on_ray_click)
	InteractionBus.ray_click_release.connect(_on_ray_click_release)
	
	hover_time = 0.0

# Runs continuosly, Use is_hovering to determine if the mouse is over the object
func _process(delta:float):
	if is_hovering:
		hover_time = delta

# Triggers when mouse is hovering over the collider.
func _on_ray_hover(collider, ray:Array):
	if self == collider:
		ray_pos = ray

# Runs once when the mouse enters this collider
# MAY BE INCONSISTENT USE ONLY WHEN NECESSARY
func _on_ray_enter(collider):
	if self == collider:
		is_hovering = true
		col_identifier = collider

# Runs once when the mouse leaves this collider
# MAY BE INCONSISTENT USE ONLY WHEN NECESSARY
func _on_ray_exit(collider):
	if self == collider:
		is_hovering = false
		_on_ray_click_release(collider)

# Runs once when a left click/tap is detected over a hovered interactable
func _on_ray_click(collider):
	if self == collider:
		is_clicked = true
		col_identifier = collider

# Runs once when a left click/tap is released over a hovered interactable
func _on_ray_click_release(collider):
	if self == collider:
		is_clicked = false
		col_identifier = null
