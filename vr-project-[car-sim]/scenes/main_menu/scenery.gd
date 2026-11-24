extends Node3D
## Scatters simple low-poly trees on both sides of the road (backdrop only).
## Uses MultiMesh so hundreds of trees cost just two draw calls.

@export var tree_count := 220
@export var road_half_width := 6.0
@export var area_width := 90.0
@export var area_length := 260.0
@export var random_seed := 1234


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.12
	trunk_mesh.bottom_radius = 0.18
	trunk_mesh.height = 1.2
	trunk_mesh.radial_segments = 6
	trunk_mesh.material = _material(Color(0.42, 0.28, 0.18))

	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.0
	crown_mesh.bottom_radius = 1.1
	crown_mesh.height = 2.8
	crown_mesh.radial_segments = 7
	crown_mesh.material = _material(Color(0.2, 0.55, 0.3))

	var trunks := _make_multimesh(trunk_mesh)
	var crowns := _make_multimesh(crown_mesh)

	for i in tree_count:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * rng.randf_range(road_half_width + 2.0, area_width * 0.5)
		var z := rng.randf_range(-area_length, 25.0)
		var s := rng.randf_range(0.7, 1.6)
		var tree_basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s)
		trunks.set_instance_transform(i, Transform3D(tree_basis, Vector3(x, 0.6 * s, z)))
		crowns.set_instance_transform(i, Transform3D(tree_basis, Vector3(x, 2.4 * s, z)))


func _make_multimesh(mesh: Mesh) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = tree_count
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	add_child(instance)
	return multimesh


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	return material
