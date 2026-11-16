@tool
extends "res://addons/starlight/StarManager.gd"
## Procedurally generates main sequence stars and populates StarManager with them.

## Radius of a sphere (or disk when flat_xz) in which to place stars.
@export var size: float = 5000: set = _set_extents
## Number of stars to generate.
@export var star_count: int = 10000: set = _set_star_count
## RNG seed, which can be used to re-roll the random generation.
@export var rng_seed: int = 1234: set = _set_rng_seed
## If set to true, a Sol-like star will be placed at 0,0,0.
@export var generate_at_origin: bool = false: set = _set_generate_at_origin
## If true, stars are placed on the XZ plane (Y = 0) instead of a full sphere.
@export var flat_xz: bool = false: set = _set_flat_xz


func _set_extents(value):
	size = value
	_generate_stars_editor()

func _set_star_count(value):
	star_count = value
	_generate_stars_editor()

func _set_rng_seed(value):
	rng_seed = value
	_generate_stars_editor()

func _set_generate_at_origin(value):
	generate_at_origin = value
	_generate_stars_editor()

func _set_flat_xz(value):
	flat_xz = value
	_generate_stars_editor()

class RangeF:
	var min: float
	var max: float

	func _init(min: float, max: float):
		self.min = min
		self.max = max

	func sample(value: float):
		return (max - min) * value + min


class StarClass:
	var weight: int
	var stellar_class: String
	var temp_range: RangeF
	var luminosity_range: RangeF
	var mass_range: RangeF

	func _init(dict: Dictionary):
		self.weight = dict.weight
		self.stellar_class = dict.stellar_class
		self.temp_range = dict.temp_range
		self.luminosity_range = dict.luminosity_range
		self.mass_range = dict.mass_range

	func sample(value: float):
		return {
			stellar_class = stellar_class,
			temp = temp_range.sample(value),
			luminosity = luminosity_range.sample(value),
			mass = mass_range.sample(value),
		}

	func get_star(position: Vector3, value: float):
		var p = self.sample(value)
		# B and O-class stars are obscenely bright, so spawn them further away than other stars.
		position *= max(1.0, p.luminosity / 400)
		return Star.new(position, p.luminosity, p.temp)


var class_O = StarClass.new({
	weight = 1,
	stellar_class = "O",
	temp_range = RangeF.new(30_000, 60_000),
	luminosity_range = RangeF.new(30_000, 60_000),
	mass_range = RangeF.new(16, 32),
})
var class_B = StarClass.new({
	weight = 13,
	stellar_class = "B",
	temp_range = RangeF.new(10_000, 30_000),
	luminosity_range = RangeF.new(25, 30_000),
	mass_range = RangeF.new(2.1, 16),
})
var class_A = StarClass.new({
	weight = 60,
	stellar_class = "A",
	temp_range = RangeF.new(7500, 10_000),
	luminosity_range = RangeF.new(5, 25),
	mass_range = RangeF.new(1.4, 2.1),
})
var class_F = StarClass.new({
	weight = 3_00,
	stellar_class = "F",
	temp_range = RangeF.new(6000, 7500),
	luminosity_range = RangeF.new(1.5, 5),
	mass_range = RangeF.new(1.04, 1.4),
})
var class_G = StarClass.new({
	weight = 7_60,
	stellar_class = "G",
	temp_range = RangeF.new(5200, 6000),
	luminosity_range = RangeF.new(.6, 1.50),
	mass_range = RangeF.new(0.8, 1.04),
})
var class_K = StarClass.new({
	weight = 12_10,
	stellar_class = "K",
	temp_range = RangeF.new(3700, 5200),
	luminosity_range = RangeF.new(0.08, 0.6),
	mass_range = RangeF.new(0.45, 0.8),
})
var class_M = StarClass.new({
	weight = 76_45,
	stellar_class = "M",
	temp_range = RangeF.new(2400, 3700),
	luminosity_range = RangeF.new(0.1, 0.08),
	mass_range = RangeF.new(0.08, 0.45),
})


var star_table = [
	class_O,
	class_B,
	class_A,
	class_F,
	class_G,
	class_K,
	class_M,
]


func sample_sphere(rng: RandomNumberGenerator, radius: float, p_flat_xz: bool = flat_xz):
	while true:
		var pos = Vector3(
			rng.randf_range(-1.0, 1.0),
			0.0 if p_flat_xz else rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		if pos.length_squared() <= 1.0:
			return pos * radius


func random_category(rng: RandomNumberGenerator):
	var sum = 0
	for category in star_table:
		sum += category.weight;

	var weight = rng.randi_range(1, sum - 1)

	sum = 0
	for category in star_table:
		var prev = sum
		sum += category.weight;
		if weight <= sum:
			return category

signal stars_generated

var _generation_thread: Thread
var _thread_mutex: Mutex
var _generated_stars_data: Array
var _generating := false

func _cache_key() -> String:
	return StarfieldCache.make_key(rng_seed, star_count, size, generate_at_origin, flat_xz)

func _apply_cached_stars(data: Array) -> void:
	var typed: Array[Star] = []
	typed.assign(data)
	set_star_list(typed)
	if material:
		material.set_shader_parameter("generation_radius", size)
	_generating = false
	stars_generated.emit()

func _force_generate_stars():
	if _generating:
		return
	# Reuse prior generation with the same params.
	if not Engine.is_editor_hint() and StarfieldCache.has_stars(_cache_key()):
		_apply_cached_stars(StarfieldCache.get_stars(_cache_key()))
		return
	_join_thread() # reap a previous, completed thread
	_generating = true
	if _thread_mutex == null:
		_thread_mutex = Mutex.new()
	_generated_stars_data = []
	_generation_thread = Thread.new()
	_generation_thread.start(
		_generate_stars_threaded.bind(rng_seed, star_count, generate_at_origin, size, flat_xz)
	)

func _join_thread() -> void:
	if _generation_thread and _generation_thread.is_started():
		_generation_thread.wait_to_finish()
	_generation_thread = null

func _generate_stars_threaded(p_rng_seed, p_star_count, p_generate_at_origin, p_size, p_flat_xz):
	# Capture table/refs locally so mid-flight free of self is less likely to UAF.
	var table: Array = star_table.duplicate()
	var sol_class = class_G
	var mutex = _thread_mutex

	var rng = RandomNumberGenerator.new()
	rng.seed = p_rng_seed

	var stars: Array[Star] = []

	if p_generate_at_origin and sol_class:
		stars.push_back(sol_class.get_star(Vector3.ZERO, 0.5))

	for i in range(0, p_star_count):
		var category = _random_category_from_table(rng, table)
		if not category:
			continue
		stars.push_back(category.get_star(_sample_sphere(rng, p_size, p_flat_xz), rng.randf()))

	if mutex:
		mutex.lock()
		_generated_stars_data = stars
		mutex.unlock()

	# Don't call into a freed node (e.g. scene torn down mid-generation).
	if is_instance_valid(self):
		call_deferred("_apply_generated_stars")

func _sample_sphere(rng: RandomNumberGenerator, radius: float, p_flat_xz: bool) -> Vector3:
	while true:
		var pos = Vector3(
			rng.randf_range(-1.0, 1.0),
			0.0 if p_flat_xz else rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)
		)
		if pos.length_squared() <= 1.0:
			return pos * radius
	return Vector3.ZERO

func _random_category_from_table(rng: RandomNumberGenerator, table: Array):
	var sum = 0
	for category in table:
		sum += category.weight

	var weight = rng.randi_range(1, sum - 1)

	sum = 0
	for category in table:
		sum += category.weight
		if weight <= sum:
			return category
	return null

func _apply_generated_stars():
	if not is_instance_valid(self):
		return
	_join_thread()
	var data: Array = []
	if _thread_mutex:
		_thread_mutex.lock()
		data = _generated_stars_data
		_thread_mutex.unlock()
	else:
		data = _generated_stars_data
	if not Engine.is_editor_hint() and not data.is_empty():
		StarfieldCache.store_stars(_cache_key(), data)
	set_star_list(data)
	if material:
		material.set_shader_parameter("generation_radius", size)
	_generating = false
	stars_generated.emit()

func _generate_stars_editor():
	if not Engine.is_editor_hint():
		return

	# Synchronous in editor for immediate feedback.
	var rng = RandomNumberGenerator.new()
	rng.seed = rng_seed

	var stars: Array[Star] = []

	if generate_at_origin:
		stars.push_back(class_G.get_star(Vector3.ZERO, 0.5))

	for i in range(0, star_count):
		var category = random_category(rng)
		if not category:
			continue

		stars.push_back(category.get_star(sample_sphere(rng, size, flat_xz), rng.randf()))

	set_star_list(stars)

	if material:
		material.set_shader_parameter("generation_radius", size)

func _exit_tree():
	_join_thread()

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		_join_thread()

func _ready():
	if not Engine.is_editor_hint():
		_force_generate_stars()

func _process(delta):
	super._process(delta)
