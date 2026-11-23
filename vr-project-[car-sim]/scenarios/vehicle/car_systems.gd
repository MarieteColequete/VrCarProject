class_name CarSystems
extends RefCounted
## The player's car's electronics in one place: its sensors ([CarSensors]) writing [member signals],
## and its control units ([AbsModule], [TransmissionUnit], [BodyController]) deciding from them.
## A step senses first, then decides; [CarDynamics] then applies what was decided, so the control
## units act on what was measured, a step behind, as real ones do.

var signals := CarSignals.new()
var abs_module := AbsModule.new()
var transmission := TransmissionUnit.new()


## Measures the plant ([method CarSensors.measure]).
func sense(dynamics: CarDynamics, motion: Dictionary, controls: Dictionary) -> void:
	CarSensors.measure(signals, dynamics, motion, controls)


## The control units' step of [param dt] seconds for the car [param spec] with [param aids].
func decide(spec: PackedFloat64Array, aids: PackedFloat64Array, dt: float) -> void:
	abs_module.step(signals, spec, aids, dt)
	transmission.step(signals, spec, dt)
	BodyController.step(signals)
