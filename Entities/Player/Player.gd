extends CharacterBody2D

const SPEED = 150.0
@onready var anim = $AnimationPlayer

var last_direction = "down"
var current_slot = null

func _input(event):
	if event.is_action_pressed("ui_accept") and current_slot:
		get_parent().open_repair_menu(current_slot)
		
func _physics_process(_delta):
	var direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	velocity = direction * SPEED
	
	if direction != Vector2.ZERO:
		if abs(direction.x) > abs(direction.y):
			if direction.x > 0:
				anim.play("walk_left")
				last_direction = "left"
			else:
				anim.play("walk_right")
				last_direction = "right"
		else:
			if direction.y > 0:
				anim.play("walk_down")
				last_direction = "down"
			else:
				anim.play("walk_up")
				last_direction = "up"
	else:
		# Quand on s'arrête, on joue l'idle correspondant à la dernière direction
		anim.play("idle_" + last_direction)

	move_and_slide()
