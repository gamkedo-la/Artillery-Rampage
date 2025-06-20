class_name TerrainChunkTextureOutlineResource extends TerrainChunkTextureResource

func _init(
	p_texture:Texture2D = null,
	p_material:Material = null,
	p_repeat: CanvasItem.TextureRepeat = CanvasItem.TextureRepeat.TEXTURE_REPEAT_DISABLED,
	p_offset: Vector2 = Vector2.ZERO
	):
		super(p_texture, p_material, p_repeat, p_offset)
		
	
func apply_to(object: Node2D, args: Array = []) -> bool:
	var outline_mesh:Line2D = object as Line2D
	if not outline_mesh:
		return super.apply_to(object, args)
	var discarded_ranges:PackedVector2Array = args[0] as PackedVector2Array if not args.is_empty() else PackedVector2Array()
	apply_to_outline(outline_mesh, discarded_ranges)
	return true
		
func apply_to_outline(line: Line2D, discarded_ranges: PackedVector2Array) -> void:
	var shader_material = material as ShaderMaterial
	if shader_material:
		var discarded_outline_indices:PackedByteArray = _compute_discarded_indices(line, discarded_ranges)
		var packed_discard_flags:PackedInt32Array = _pack_discard_flags(discarded_outline_indices)
		shader_material.set_shader_parameter("discarded_vertex_flags", packed_discard_flags)
	line.material = material
	line.set_texture(texture)
	line.texture_repeat = repeat
	# Line2D doesn't support texture_offset


static func _compute_discarded_indices(line: Line2D, discarded_ranges: PackedVector2Array)  -> PackedByteArray:
	discarded_ranges.sort()
	# TODO: Need to match the line points against the input ranges
	# TODO: The ranges also need to be compute in replace_contents and utilize the new get_destroyed_range function
	var index_flags:PackedByteArray = []
	# Need to multiply by 2 because it turns the line into a polygon and half the vertices will be the top and half the bottom so everything has to be roughly doubled
	index_flags.resize(line.points.size() * 2)

	# 1 discards and 0 draws
	index_flags.fill(0)
	
	return index_flags

## Packs the bool array of discard flags corresponding to vertex indices into an int32 flag array to compress it by a factor of 32 for the shader parameter
## Shader parameters don't support bool[] or byte[] and only int[]
static func _pack_discard_flags(flags: PackedByteArray) -> PackedInt32Array:
	var packed: PackedInt32Array = []
	# Preallocate the buffer
	packed.resize(ceili(flags.size() / 32.0))
	
	var current:int = 0
	var count:int = 0
	
	for i in flags.size():
		var bit:int = flags[i] & 1
		current |= bit << (i % 32)
		if i % 32 == 31:
			packed[count] = current
			current = 0
			count += 1
	# Set last bit information
	if current != 0:
		packed[count] = current
	return packed
