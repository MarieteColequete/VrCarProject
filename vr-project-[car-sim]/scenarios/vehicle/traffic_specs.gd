class_name TrafficSpecs
extends RefCounted
## The road users' cars: the specs they drive on ([CarSpec]), packed once on the main thread, and
## which a road user takes by its size. A road user's [code]spec[/code] column is its index here.

const PATHS: Array[String] = [
	"res://scenarios/vehicle/specs/hatchback.tres",
	"res://scenarios/vehicle/specs/saloon.tres",
	"res://scenarios/vehicle/specs/van.tres",
	"res://scenarios/vehicle/specs/lorry.tres",
]
const HATCHBACK := 0
const SALOON := 1
const VAN := 2
const LORRY := 3

static var _packed: Array = []


## Every spec packed, by index. Main thread: loads them the first time.
static func all() -> Array:
	if _packed.is_empty():
		for path in PATHS:
			_packed.append((load(path) as CarSpec).packed())
	return _packed


## The spec a road user of [param size] (width, height, length, metres) drives: a hatchback up to
## 4.4 m long, a saloon up to 5.5 m, a van up to 7.5 m, and a lorry beyond.
static func pick(size: Vector3) -> int:
	if size.z <= 4.4:
		return HATCHBACK
	if size.z <= 5.5:
		return SALOON
	if size.z <= 7.5:
		return VAN
	return LORRY
