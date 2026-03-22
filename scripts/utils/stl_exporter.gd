## STLExporter — converts CAD objects to binary STL files.
##
## Binary STL is the standard format for 3D printers and most CNC toolchain
## programs. This exporter:
##   1. Collects all CADObjects (or a specific selection) from the scene.
##   2. Retrieves each object's mesh, applies its world transform.
##   3. Triangulates quads (Godot meshes may contain quad primitives).
##   4. Writes a valid binary STL to the given path.
##
## Usage:
##   STLExporter.export_all("user://my_design.stl")
##   STLExporter.export_selection([box_node, cyl_node], "user://my_design.stl")
extends RefCounted

# ─── Public API ──────────────────────────────────────────────────────────────

## Export every CADObject in the scene to a single merged STL.
static func export_all(filepath: String) -> Error:
	var objects: Array[Node3D] = []
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		push_error("STLExporter: No scene tree available.")
		return ERR_UNAVAILABLE

	for node in tree.get_nodes_in_group("cad_objects"):
		if node is Node3D:
			objects.append(node as Node3D)

	if objects.is_empty():
		push_warning("STLExporter: No CAD objects found in scene.")
		return ERR_DOES_NOT_EXIST

	return export_selection(objects, filepath)


## Export a specific list of Node3D objects.
static func export_selection(objects: Array[Node3D], filepath: String) -> Error:
	var triangles: Array[PackedVector3Array] = []

	for obj in objects:
		var mesh_inst := _find_mesh_instance(obj)
		if mesh_inst == null:
			continue
		var mesh := mesh_inst.mesh
		if mesh == null:
			continue
		_extract_triangles(mesh, obj.global_transform, triangles)

	if triangles.is_empty():
		push_warning("STLExporter: No geometry to export.")
		return ERR_DOES_NOT_EXIST

	return _write_binary_stl(filepath, triangles)


# ─── Triangle extraction ─────────────────────────────────────────────────────

static func _extract_triangles(
	mesh: Mesh,
	world_xf: Transform3D,
	out_triangles: Array[PackedVector3Array]
) -> void:
	for surface_idx in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_idx)
		if arrays.is_empty():
			continue

		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]  # PackedInt32Array or null

		var primitive: int = mesh.surface_get_primitive_type(surface_idx)

		# Transform vertices to world space
		var world_verts := PackedVector3Array()
		world_verts.resize(verts.size())
		for i in range(verts.size()):
			world_verts[i] = world_xf * verts[i]

		match primitive:
			Mesh.PRIMITIVE_TRIANGLES:
				if indices != null and indices.size() > 0:
					_triangles_from_indexed(world_verts, indices, out_triangles)
				else:
					_triangles_from_sequential(world_verts, out_triangles)

			Mesh.PRIMITIVE_TRIANGLE_STRIP:
				_triangles_from_strip(world_verts, out_triangles)

			_:
				push_warning("STLExporter: Unsupported primitive type %d — skipped." % primitive)


static func _triangles_from_indexed(
	verts: PackedVector3Array,
	indices: PackedInt32Array,
	out: Array[PackedVector3Array]
) -> void:
	var i := 0
	while i + 2 < indices.size():
		var tri := PackedVector3Array([
			verts[indices[i]],
			verts[indices[i + 1]],
			verts[indices[i + 2]],
		])
		out.append(tri)
		i += 3


static func _triangles_from_sequential(
	verts: PackedVector3Array,
	out: Array[PackedVector3Array]
) -> void:
	var i := 0
	while i + 2 < verts.size():
		out.append(PackedVector3Array([verts[i], verts[i + 1], verts[i + 2]]))
		i += 3


static func _triangles_from_strip(
	verts: PackedVector3Array,
	out: Array[PackedVector3Array]
) -> void:
	for i in range(2, verts.size()):
		if i % 2 == 0:
			out.append(PackedVector3Array([verts[i - 2], verts[i - 1], verts[i]]))
		else:
			out.append(PackedVector3Array([verts[i - 1], verts[i - 2], verts[i]]))


# ─── Binary STL writer ───────────────────────────────────────────────────────
#
# Binary STL format:
#   [80 bytes] ASCII header (unused, zero-padded)
#   [4 bytes]  uint32  — triangle count
#   For each triangle (50 bytes):
#     [12 bytes] float32 × 3  — face normal
#     [12 bytes] float32 × 3  — vertex 0
#     [12 bytes] float32 × 3  — vertex 1
#     [12 bytes] float32 × 3  — vertex 2
#     [2 bytes]  uint16       — attribute byte count (always 0)

static func _write_binary_stl(
	filepath: String,
	triangles: Array[PackedVector3Array]
) -> Error:
	var file := FileAccess.open(filepath, FileAccess.WRITE)
	if file == null:
		push_error("STLExporter: Cannot open '%s' for writing: %s" % [
			filepath, error_string(FileAccess.get_open_error())
		])
		return FileAccess.get_open_error()

	# 80-byte header
	var header := PackedByteArray()
	header.resize(80)
	header.fill(0)
	var tag := "VR-CAD Export"
	for i in range(min(tag.length(), 80)):
		header[i] = tag.unicode_at(i)
	file.store_buffer(header)

	# Triangle count (little-endian uint32)
	file.store_32(triangles.size())

	# Triangles
	for tri in triangles:
		if tri.size() < 3:
			continue
		var v0: Vector3 = tri[0]
		var v1: Vector3 = tri[1]
		var v2: Vector3 = tri[2]

		# Compute face normal (outward by right-hand rule)
		var normal: Vector3 = (v1 - v0).cross(v2 - v0).normalized()

		# Normal
		file.store_float(normal.x)
		file.store_float(normal.y)
		file.store_float(normal.z)

		# Vertices
		for v in [v0, v1, v2]:
			file.store_float(v.x)
			file.store_float(v.y)
			file.store_float(v.z)

		# Attribute byte count
		file.store_16(0)

	file.close()

	print("STLExporter: Wrote %d triangles to '%s'" % [triangles.size(), filepath])
	return OK


# ─── Helpers ─────────────────────────────────────────────────────────────────

static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null


## Returns the suggested export path in the user:// directory.
static func get_default_export_path(filename: String = "export.stl") -> String:
	return "user://" + filename


## Convert user:// path to an OS-level path for display.
static func user_path_to_os(user_path: String) -> String:
	return ProjectSettings.globalize_path(user_path)
