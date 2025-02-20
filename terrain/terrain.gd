class_name Terrain extends Node2D

const TerrainChunkScene = preload("res://terrain/terrain_chunk.tscn")

@export var smooth_offset: float = 3
@export var falling_offset: float = 3

var initial_chunk_name: String
var first_child_chunk: TerrainChunk

func _ready():
	first_child_chunk = get_child(0)
	initial_chunk_name = first_child_chunk.name

# Based on https://www.youtube.com/watch?v=FiKsyOLacwA
# poly_scale will determine the size of the explosion that destroys the terrain
	
func damage(terrainChunk: TerrainChunk, projectile_poly: CollisionPolygon2D, poly_scale: Vector2 = Vector2(1,1)):
	
	#print("Clipping terrain with polygon:", projectile_poly.polygon)
	var scale_transform: Transform2D = Transform2D(0, poly_scale, 0, Vector2())
	# Combine the scale transform with the world (global) transform
	var combined_transform: Transform2D = projectile_poly.global_transform * scale_transform
	
	var projectile_poly_global: PackedVector2Array = combined_transform * projectile_poly.polygon
	
	# Transform terrain polygon to world space
	var terrain_poly_global: PackedVector2Array = terrainChunk.get_terrain_global()

	#print("clip - terrain poly in world space")
	#print_poly(terrain_poly_global)
	
	# Do clipping operations in global space
	var clipping_results = Geometry2D.clip_polygons(terrain_poly_global, projectile_poly_global)
	
	# This means the chunk was destroyed so we need to queue_free
	if clipping_results.is_empty():
		print("damage(" + name + ") completely destroyed by poly=" + projectile_poly.owner.name)
		terrainChunk.delete()
		return
	
	var updated_terrain_poly = clipping_results[0]
	print("damage(" + name + ") Clip result with " + projectile_poly.owner.name +
	 " - Changing from size of " + str(terrain_poly_global.size()) + " to " + str(updated_terrain_poly.size()))

	#print("old poly (WORLD):")
	#print_poly(terrain_poly_global)
	#print("new poly (WORLD):")
	#print_poly(updated_terrain_poly)
	
	terrainChunk.replace_contents(updated_terrain_poly)
	
	# We updated the current chunk and no more chunks to add 
	if clipping_results.size() == 1:
		return
		
	_add_new_chunks(first_child_chunk, clipping_results, 1)
	
func _add_new_chunks(first_chunk: TerrainChunk,
 geometry_results: Array[PackedVector2Array], start_index: int) -> void:
	# Create additional terrain pieces for the remaining geometry results
	
	for i in range(start_index, geometry_results.size()):
		var new_clip_poly = geometry_results[i]

		# Ignore clockwise results as these are "holes" and need to handle these differently later
		if _is_invisible(new_clip_poly):
			print("_add_new_chunks(" + name + ") Ignoring 'hole' polygon for clipping result[" + str(i) + "] of size " + str(new_clip_poly.size()))
			continue
			
		var current_child_count: int = get_child_count()		
		var new_chunk_name = initial_chunk_name + str(i + current_child_count)
		
		print("_add_new_chunks(" + name + ") Creating new terrain chunk(" + new_chunk_name + ") for clipping result[" + str(i) + "] of size " + str(new_clip_poly.size()))
		_add_new_chunk(first_chunk, new_chunk_name, new_clip_poly)
		

static func _is_invisible(poly: PackedVector2Array) -> bool:
	return poly.size() < 3 or Geometry2D.is_polygon_clockwise(poly)

static func _is_visible(poly: PackedVector2Array) -> bool:
	return !_is_invisible(poly)
	
func _add_new_chunk(prototype_chunk: TerrainChunk, chunk_name: String, new_clip_poly: PackedVector2Array) -> void:
	var new_chunk = TerrainChunkScene.instantiate()
	new_chunk.name = chunk_name
	# By definition a disconnected chunk could be falling so we will let it test for that
	new_chunk.falling = true
	
	add_child(new_chunk)
	# Must be done after adding as a child
	new_chunk.owner = self
	
	# Put the new chunk with same positioning was existing
	new_chunk.global_transform = prototype_chunk.global_transform
	new_chunk.z_index = prototype_chunk.z_index

	new_chunk.replace_contents(new_clip_poly)

static func _largest_poly_first(a: PackedVector2Array, b: PackedVector2Array) -> bool:
	return a.size() > b.size()


func _morph_falling_chunk(chunk: TerrainChunk) -> PackedVector2Array:
	var falling_transform: Transform2D = Transform2D(0, Vector2(0, falling_offset))
	var chunk_poly = falling_transform * chunk.get_terrain_global()

	# now apply the smoothing offset
	# TODO: This causes way too many polygons to be generated and the frame rate craters
	# var results := Geometry2D.offset_polygon(chunk_poly, smooth_offset, Geometry2D.JOIN_ROUND)
	# return results[0] if results.size() >= 1 else []
	return chunk_poly

func merge_chunks(in_first_chunk: TerrainChunk, in_second_chunk: TerrainChunk) -> void:
	var largest_is_first := in_first_chunk.compare(in_second_chunk)
	var first_chunk := in_first_chunk if largest_is_first else in_second_chunk
	var second_chunk := in_second_chunk if largest_is_first else in_first_chunk
		
	var first_poly: PackedVector2Array
	var second_poly: PackedVector2Array 
	
	# If the chunk is falling then need to offset it
	if first_chunk.falling:
		first_poly = _morph_falling_chunk(first_chunk)
	else:
		first_poly = first_chunk.get_terrain_global()
	
	if second_chunk.falling:
		second_poly = _morph_falling_chunk(second_chunk)
	else:
		second_poly = second_chunk.get_terrain_global()

	var results: Array[PackedVector2Array] = Geometry2D.merge_polygons(first_poly, second_poly)

	print("merge_chunks: first(%d) + second(%d) -> %d: [%s]"
	 % [first_poly.size(), second_poly.size(), results.size(),
	 ",".join(results.map(func(x : PackedVector2Array): return x.size()))])
	
	# Sort by size so we can keep the largest
	results.sort_custom(_largest_poly_first)
	
	if results.size() >= 1 and _is_visible(results[0]):
		first_chunk.replace_contents(results[0])
	else:
		first_chunk.delete()
	
	if results.size() >= 2 and _is_visible(results[1]):
		second_chunk.replace_contents(results[1])
	else:
		second_chunk.delete()
		
	if results.size() >= 3:
		_add_new_chunks(first_child_chunk, results, 2)
		
	print("merge_chunks: final terrain chunk count=%d" % [get_child_count()])
