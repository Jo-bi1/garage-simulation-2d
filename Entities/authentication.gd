extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Firebase.Auth.login_succeeded.connect(on_login_succeeded)
	Firebase.Auth.signup_succeeded.connect(on_signup_succeeded)
	Firebase.Auth.login_failed.connect(on_login_failed)
	Firebase.Auth.signup_failed.connect(on_signup_failed)
	
	%State.text = "Entrez email/mot de passe"  # Init

	# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_login_button_pressed() -> void:
	var email = %EmailLineEdit.text
	var password = %PasswordLineEdit.text  # ← "passsword" → "password"
	Firebase.Auth.login_with_email_and_password(email, password)  # ← login (pas login_with)
	%State.text = "Logging in..."
	

func _on_sign_up_button_pressed() -> void:
	var email = %EmailLineEdit.text
	var password = %PasswordLineEdit.text  # ← idem
	Firebase.Auth.signup_with_email_and_password(email, password)  # ← signup_with
	%State.text = "Signing up..."
func on_login_succeeded(auth: Dictionary) -> void:
	var token = auth.get("idtoken", "")
	var email = auth.get("email", "")

	print("✅ Login OK pour ", email)

	# Charge la scène World
	var world_packed: PackedScene = load("res://scenes/Main/World.tscn")  # ← chemin exact à vérifier
	if world_packed == null:
		push_error("World.tscn introuvable")
		return

	# Instancie World et passe les infos
	var world = world_packed.instantiate()
	world.auth_token = token
	world.user_email = email

	# Affiche World et ferme l'écran de login
	get_tree().root.add_child(world)
	queue_free()

func on_signup_succeeded(auth: Dictionary):
	print("✅ Signup: ", auth)
	%State.text = "✅ Signup OK! Vérification envoyée."
	# 🔥 CORRECT API
	Firebase.Auth.send_account_verification_email()  # ← Ça marche !

func on_login_failed(error_code: int, message: String):
	%State.text = "❌ Login: %s (code %d)" % [message, error_code]

func on_signup_failed(error_code: int, message: String):
	%State.text = "❌ Signup: %s (code %d)" % [message, error_code]
