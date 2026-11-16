class_name StarfieldCache
extends RefCounted

## In-memory cache of procedurally generated star lists, keyed by generation params.
## No project autoload required — StarGenerator uses this via class_name.

static var _stars_by_key: Dictionary = {} # String -> Array


static func make_key(
	rng_seed: int,
	p_star_count: int,
	size: float,
	generate_at_origin: bool,
	flat_xz: bool
) -> String:
	return "%d_%d_%.3f_%s_%s" % [
		rng_seed, p_star_count, size, str(generate_at_origin), str(flat_xz)
	]


static func has_stars(key: String) -> bool:
	return _stars_by_key.has(key) and not _stars_by_key[key].is_empty()


static func get_stars(key: String) -> Array:
	return _stars_by_key.get(key, [])


static func store_stars(key: String, data: Array) -> void:
	if data.is_empty():
		return
	_stars_by_key[key] = data
