extends Control

func _ready() -> void:
	Firebase.Auth.login_succeeded.connect(on_login_succeeded)
	Firebase.Auth.signup_succeeded.connect(on_signup_succeeded)
	Firebase.Auth.login_failed.connect(on_login_failed)
	Firebase.Auth.signup_failed.connect(on_signup_failed)
	
	%State.text = "Entrez email/mot de passe"


func _process(delta: float) -> void:
	pass


func _on_login_button_pressed() -> void:
	var email = %EmailLineEdit.text
	var password = %PasswordLineEdit.text
	Firebase.Auth.login_with_email_and_password(email, password)
	%State.text = "Logging in..."


func _on_sign_up_button_pressed() -> void:
	var email = %EmailLineEdit.text
	var password = %PasswordLineEdit.text
	Firebase.Auth.signup_with_email_and_password(email, password)
	%State.text = "Signing up..."


func on_login_succeeded(auth: Dictionary) -> void:
	print("✅ Login OK pour %s" % auth.get("email", ""))

	var world_packed: PackedScene = load("res://scenes/Main/World.tscn")
	var world: Node = world_packed.instantiate()
	world.init_auth(auth)

	# On switch de scène au frame suivant pour éviter "free locked object"
	call_deferred("_switch_to_world", world)


func _switch_to_world(world: Node) -> void:
	get_tree().root.add_child(world)
	get_tree().current_scene.queue_free()
	get_tree().current_scene = world


func on_signup_succeeded(auth: Dictionary) -> void:
	print("✅ Signup: ", auth)
	%State.text = "✅ Signup OK! Vérification envoyée."
	Firebase.Auth.send_account_verification_email()


func on_login_failed(error_code: int, message: String) -> void:
	%State.text = "❌ Login: %s (code %d)" % [message, error_code]


func on_signup_failed(error_code: int, message: String) -> void:
	%State.text = "❌ Signup: %s (code %d)" % [message, error_code]
