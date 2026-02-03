extends Control

var car_panels = {}

func _ready():
	for panel in $VBoxContainer.get_children():
		var label = panel.get_node("Label")
		var bar = panel.get_node("ProgressBar")
		car_panels[label.text] = bar

func add_car(car_name: String):
	for panel in $VBoxContainer.get_children():
		var label = panel.get_node("Label")
		var bar = panel.get_node("ProgressBar")
		if label.text == "":
			label.text = car_name
			bar.value = 0
			car_panels[car_name] = bar
			break

func update_progress(car_name: String, value: float):
	if car_panels.has(car_name):
		car_panels[car_name].value = clamp(value, 0, 100)

func remove_car(car_name: String):
	if car_panels.has(car_name):
		for panel in $VBoxContainer.get_children():
			if panel.get_node("Label").text == car_name:
				panel.get_node("Label").text = ""
				panel.get_node("ProgressBar").value = 0
				break
		car_panels.erase(car_name)
