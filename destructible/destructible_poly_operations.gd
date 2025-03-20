class_name DestructiblePolyOperations extends Node

@export_category("Smoothing")
@export var smooth_y_threshold_pct: float = 0.5

@export_category("Smoothing")
# Sometimes the algorithm flags things incorrectly that are essentially vertical drops near the left of screen
@export var smooth_x_threshold_diff: float = 10

@export_category("Crumbling")
@export var crumble_y_min_dist: float = 1

@export_category("Crumbling")
@export var crumble_x_min_dist: float = 50

@export_category("Crumbling")
@export var crack_delta_min: float = 5

@export_category("Crumbling")
@export var crack_delta_max: float = 25

@export_category("Crumbling")
@export_range(0, 100) var crumble_y_step_min: float = 5

@export_category("Crumbling")
@export_range(0, 100) var crumble_y_step_max: float = 50

@export_category("Crumbling")
@export_range(0, 100) var crumble_x_jitter: float = 10


func smooth(poly: PackedVector2Array, bounds: Circle) -> PackedVector2Array:
		
	# Polygon is actually stored clockwise. Look at vertices and see where x decreases indicating a dent until we start winding around
	# Don't modify the interior of the terrain. Detect this by looking at the maximum y (bottom-most point)
	var bottom_y: float = -1e12
	var top_y: float = 1e12
	for vec in poly:
		if vec.y > bottom_y : bottom_y = vec.y
		elif vec.y < top_y : top_y = vec.y
	var threshold_y: float = (bottom_y - top_y) * smooth_y_threshold_pct + bottom_y
	
	var smooth_updates: int = 0
 	
	for i in range(1, poly.size()):
		var current := poly[i]
		var prev := poly[i - 1]

		# Don't modify the bottom
		if current.x - prev.x < -smooth_x_threshold_diff and current.y < prev.y and current.y < threshold_y and bounds.contains(current):
			poly[i] = (prev + current) * 0.5
			smooth_updates += 1
	#		if i > 1 and absf(poly[i - 1].y - bottom_y) > smooth_y_threshold_value:
	#			poly[i - 1] = (prev + poly[i - 2]) * 0.5
	#			smooth_updates += 1
	
	if smooth_updates:
		print_debug("Chunk(%s) - _smooth: Changed %d verticies" % [get_parent().name, smooth_updates])
		
	return poly

# Always returns at least the input poly chunk in the returned array
func crumble(poly: PackedVector2Array, bounds: Circle) -> Array[PackedVector2Array]:
	var final_chunk_polys: Array[PackedVector2Array] = []
	
	var x_sum:float = 0.0
	var first_hanging:int = 0
	var hanging_count:int = 0
	
	for i in range(1, poly.size()):
		var vertex := poly[i]
		# We've gone outside the influence area - reset and try next vertex
		var vertex_hanging:bool = true
		if !bounds.contains(vertex):
			vertex_hanging = false
		# Determine if current vertex is at the bottom or top of chunk by checking small y offset to see if it is inside
		elif Geometry2D.is_point_in_polygon(vertex + Vector2(0, crumble_y_min_dist), poly):
			vertex_hanging = false	
		
		if vertex_hanging:
			x_sum += absf(poly[i].x - poly[i - 1 if i > 0 else poly.size() - 1].x)
			if hanging_count == 0:
				hanging_count = 1
				first_hanging = i
			else:
				hanging_count += 1
			
		# We've stopped hanging or on last vertex, check to see if we can cut a chunk
		# TODO: Maybe take thickness into account
		if (!vertex_hanging or i == poly.size() - 1) and hanging_count > 0 and x_sum >= crumble_x_min_dist:
			# Cut a jagged polygon up through the first hanging point and add the results when > 1 to output
			# Keep largest piece on this chunk?
			var crumble_chunks := _calculate_crumble(poly, first_hanging, hanging_count)
			# TODO: Need to break here or things get too complex if need to break it multiple times in one go
			if crumble_chunks.size() > 1:
				final_chunk_polys.append_array(crumble_chunks)
				break
				
		if !vertex_hanging:
			hanging_count = 0
			x_sum = 0.0
	# for
	
	if final_chunk_polys.is_empty():	
		final_chunk_polys.push_back(poly)
		
	return final_chunk_polys

func _calculate_crumble(poly: PackedVector2Array, first_index: int, count: int) -> Array[PackedVector2Array]:

	print_debug("Chunk(%s) - poly=%d; first_index=%d; count=%d" % [get_parent().name, poly.size(), first_index, count])

	# See https://forum.godotengine.org/t/cut-a-polygon-with-a-polyline-not-the-contrary/17710/3
	# See https://github.com/goostengine/goost/discussions/132
	var polyline := _create_break_polyline(poly, first_index)
	
	# Restrict to poly
	#var results := Geometry2D.clip_polyline_with_polygon(polyline, poly)
	#if results.is_empty():
	#	return []
	#polyline = results[0]
	
	var crack_delta: float = randf_range(crack_delta_min, crack_delta_max)
	var polygon_cut := Geometry2D.offset_polyline(polyline, crack_delta, Geometry2D.JOIN_SQUARE)
	if polygon_cut.is_empty():
		print_debug("Chunk(%s) - Could not crumble as polyline was invalid" % [get_parent().name])
		return []
	
	var clip_results := Geometry2D.clip_polygons(poly, polygon_cut[0])
	 
	print_debug("Chunk(%s) - raw clip result - %d:[%s]" % 
		[get_parent().name, clip_results.size(), ",".join(clip_results.map(func(c : PackedVector2Array): return c.size()))])

	clip_results = clip_results.filter(
		func(result:PackedVector2Array):
			return TerrainUtils.is_visible(result)
	)
	clip_results.sort_custom(TerrainUtils.largest_poly_first)
	
	print_debug("Chunk(%s) - final clip result - %d:[%s]" % 
	[get_parent().name, clip_results.size(), ",".join(clip_results.map(func(c : PackedVector2Array): return c.size()))])

	return clip_results
	
func _create_break_polyline(poly: PackedVector2Array, first_index: int) -> PackedVector2Array:
	var polyline: PackedVector2Array = []
	
	var viewport := (get_parent() as Node2D).get_viewport_rect()
		
	# Cut up through the first_index x and y with jitter applied
	# TODO: Can probably reduce the number of points here based on the world position of the poly
	# Right now the poly points are in local space
	var height = viewport.size.y * 0.5
	
	var first_point := poly[first_index]	
	var delta_y:float = 0
	var delta_point := Vector2(0, 1)
	
	while delta_y < height:
		polyline.push_back(first_point + delta_point)
		
		# Negate y to move up 
		var y_step: float = randf_range(crumble_y_step_min, crumble_y_step_max)
		delta_y += y_step
		
		delta_point = Vector2(
			randf_range(-crumble_x_jitter, crumble_x_jitter),
			-delta_y)
	
	return polyline
