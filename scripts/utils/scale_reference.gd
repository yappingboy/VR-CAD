## ScaleReference — places 1:1 scale ghost objects in the scene so you can
## verify that your design will fit in the real world.
##
## Included references:
##   • human_adult    — 1.75 m tall human silhouette
##   • hand           — average adult hand outline
##   • ruler_10cm     — 10 cm ruler marker
##   • ruler_1m       — 1 m ruler marker
##   • credit_card    — 85.6 × 54 mm card
##   • a4_paper       — 210 × 297 mm sheet
##   • custom         — any user-specified dimensions
##
## Ghost objects are semi-transparent wireframe overlays so they don't
## obscure the passthrough or the CAD model.
extends Node3D

signal reference_added(ref_id: String)
signal reference_removed(ref_id: String)

# ─── Reference definitions ───────────────────────────────────────────────────

const REFERENCES: Dictionary = {
	"human_adult": {
		"label": "Adult Human (1.75 m)",
		"size":  Vector3(0.45, 1.75, 0.25),
		"color": Color(0.8, 0.6, 0.2, 0.35),
	},
	"hand": {
		"label": "Adult Hand (~20 cm)",
		"size":  Vector3(0.09, 0.20, 0.025),
		"color": Color(0.8, 0.6, 0.2, 0.35),
	},
	"ruler_10cm": {
		"label": "10 cm ruler",
		"size":  Vector3(0.10, 0.002, 0.015),
		"color": Color(0.2, 0.9, 0.3, 0.6),
	},
	"ruler_1m": {
		"label": "1 m ruler",
		"size":  Vector3(1.0, 0.002, 0.03),
		"color": Color(0.2, 0.9, 0.3, 0.6),
	},
	"credit_card": {
		"label": "Credit card (85.6 × 54 mm)",
		"size":  Vector3(0.0856, 0.054, 0.001),
		"color": Color(0.5, 0.5, 1.0, 0.5),
	},
	"a4_paper": {
		"label": "A4 paper (210 × 297 mm)",
		"size":  Vector3(0.210, 0.001, 0.297),
		"color": Color(0.9, 0.9, 0.9, 0.4),
	},
}

# ─── State ───────────────────────────────────────────────────────────────────

var _active_refs: Dictionary = {}  # ref_id → Node3D


# ─── Public API ──────────────────────────────────────────────────────────────

## Spawn a reference ghost at `world_position`.
## Returns the Node3D so callers can move it further if needed.
func add_reference(ref_id: String, world_position: Vector3) -> Node3D:
	if ref_id in _active_refs:
		remove_reference(ref_id)

	var def: Dictionary = REFERENCES.get(ref_id, {})
	if def.is_empty():
		push_warning("ScaleReference: Unknown ref_id '%s'" % ref_id)
		return null

	var ghost := _make_ghost(def["size"], def["color"], def["label"])
	ghost.global_position = world_position
	add_child(ghost)
	_active_refs[ref_id] = ghost

	reference_added.emit(ref_id)
	return ghost


## Spawn a custom-sized ghost (width, height, depth in metres).
func add_custom_reference(
	ref_id: String,
	size_m: Vector3,
	world_position: Vector3,
	color: Color = Color(1.0, 0.8, 0.0, 0.4)
) -> Node3D:
	if ref_id in _active_refs:
		remove_reference(ref_id)

	var ghost := _make_ghost(size_m, color, "Custom (%s mm)" % _vec_to_mm_str(size_m))
	ghost.global_position = world_position
	add_child(ghost)
	_active_refs[ref_id] = ghost

	reference_added.emit(ref_id)
	return ghost


func remove_reference(ref_id: String) -> void:
	if ref_id in _active_refs:
		_active_refs[ref_id].queue_free()
		_active_refs.erase(ref_id)
		reference_removed.emit(ref_id)


func remove_all_references() -> void:
	for ref_id in _active_refs.keys():
		remove_reference(ref_id)


func toggle_reference(ref_id: String, world_position: Vector3) -> void:
	if ref_id in _active_refs:
		remove_reference(ref_id)
	else:
		add_reference(ref_id, world_position)


func get_active_references() -> Array[String]:
	var ids: Array[String] = []
	for k in _active_refs:
		ids.append(k)
	return ids


# ─── Ghost construction ──────────────────────────────────────────────────────

func _make_ghost(size: Vector3, color: Color, label_text: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Ghost"

	# Solid face with alpha
	var solid_mesh := BoxMesh.new()
	solid_mesh.size = size

	var solid_mat := StandardMaterial3D.new()
	solid_mat.albedo_color = color
	solid_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	solid_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	solid_mat.no_depth_test = false
	solid_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var solid_inst := MeshInstance3D.new()
	solid_inst.mesh = solid_mesh
	solid_inst.material_override = solid_mat
	solid_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(solid_inst)

	# Wireframe edges using line segments
	var wire_inst := _make_wire_box(size, color.lightened(0.4))
	root.add_child(wire_inst)

	# Label3D floating above
	var lbl := Label3D.new()
	lbl.text = label_text
	lbl.font_size = 20
	lbl.modulate = color.lightened(0.5)
	lbl.position = Vector3(0, size.y * 0.5 + 0.02, 0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	root.add_child(lbl)

	return root


func _make_wire_box(size: Vector3, color: Color) -> MeshInstance3D:
	var half: Vector3 = size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half.x, -half.y, -half.z), Vector3( half.x, -half.y, -half.z),
		Vector3( half.x, -half.y,  half.z), Vector3(-half.x, -half.y,  half.z),
		Vector3(-half.x,  half.y, -half.z), Vector3( half.x,  half.y, -half.z),
		Vector3( half.x,  half.y,  half.z), Vector3(-half.x,  half.y,  half.z),
	]
	# 12 edges of a box
	var edges: Array[Array] = [
		[0,1],[1,2],[2,3],[3,0],  # bottom
		[4,5],[5,6],[6,7],[7,4],  # top
		[0,4],[1,5],[2,6],[3,7],  # verticals
	]

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(color)
	for edge in edges:
		st.add_vertex(corners[edge[0]])
		st.add_vertex(corners[edge[1]])

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = false

	var inst := MeshInstance3D.new()
	inst.mesh = st.commit()
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return inst


# ─── Ruler tool ──────────────────────────────────────────────────────────────

## Draw a measurement line between two world points.
## Returns the measuring node so the caller can remove it later.
func measure_between(point_a: Vector3, point_b: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "Measurement"
	add_child(root)

	var distance: float = point_a.distance_to(point_b)
	var mid: Vector3 = (point_a + point_b) * 0.5

	# Line
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.set_color(Color(1.0, 0.9, 0.0, 1.0))
	st.add_vertex(point_a)
	st.add_vertex(point_b)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var line := MeshInstance3D.new()
	line.mesh = st.commit()
	line.material_override = mat
	root.add_child(line)

	# Distance label
	var lbl := Label3D.new()
	var mm: float = distance * 1000.0
	if mm >= 10.0:
		lbl.text = "%.1f mm" % mm
	else:
		lbl.text = "%.2f mm" % mm
	lbl.global_position = mid + Vector3(0, 0.02, 0)
	lbl.font_size = 24
	lbl.modulate = Color(1.0, 0.95, 0.2)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	root.add_child(lbl)

	return root


# ─── Helpers ─────────────────────────────────────────────────────────────────

func _vec_to_mm_str(v: Vector3) -> String:
	return "%.0f × %.0f × %.0f" % [v.x * 1000.0, v.y * 1000.0, v.z * 1000.0]
