class_name BodyController
extends RefCounted
## The player's car's body controller: its lamps from their switches ([CarSignals]), as wired in a
## real car. The brake lights follow the brake pedal's switch, whatever the car is doing; the
## reversing lights follow the gearbox's reverse switch, not the car rolling backward.


static func step(signals: CarSignals) -> void:
	signals.brake_light = signals.brake_switch
	signals.reverse_light = signals.reverse_switch
