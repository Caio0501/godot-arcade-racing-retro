@tool
extends Node3D
## Gera o landscape de teste de arte: terreno com colinas, estrada em loop,
## lago e vegetação espalhada (árvores de outono, pinheiros e pedras).
## Tudo é procedural a partir de `seed`; use o botão "Regenerar" no inspetor.

const OAKS := [
	"res://assets/environment/trees/OakTree1.fbx",
	"res://assets/environment/trees/OakTree2.fbx",
	"res://assets/environment/trees/OakTree3.fbx",
]
const SPRUCES := [
	"res://assets/environment/trees/SpruceTree1.fbx",
	"res://assets/environment/trees/SpruceTree2.fbx",
	"res://assets/environment/trees/SpruceTree3.fbx",
]
const DEAD_TREES := [
	"res://assets/environment/trees/DeadOak1.fbx",
	"res://assets/environment/trees/DeadOak2.fbx",
	"res://assets/environment/trees/DeadSpruce1.fbx",
]
const ROCKS := [
	"res://assets/environment/rocks/Rock1.fbx", "res://assets/environment/rocks/Rock2.fbx",
	"res://assets/environment/rocks/Rock3.fbx", "res://assets/environment/rocks/Rock4.fbx",
	"res://assets/environment/rocks/Rock5.fbx", "res://assets/environment/rocks/Rock6.fbx",
	"res://assets/environment/rocks/Rock7.fbx", "res://assets/environment/rocks/Rock8.fbx",
	"res://assets/environment/rocks/Rock_12.fbx", "res://assets/environment/rocks/Rock_16.fbx",
	"res://assets/environment/rocks/Rock_20.fbx", "res://assets/environment/rocks/Rock_24.fbx",
]
const BIG_ROCKS := [
	"res://assets/environment/rocks/BigRock1.fbx", "res://assets/environment/rocks/BigRock2.fbx",
	"res://assets/environment/rocks/BigRock3.fbx", "res://assets/environment/rocks/BigRock4.fbx",
	"res://assets/environment/rocks/BigRock5.fbx",
]

# Pontos de controle da estrada (XZ), em loop fechado.
const ROAD_POINTS := [
	Vector2(0, -130), Vector2(60, -122), Vector2(110, -82), Vector2(125, -20),
	Vector2(98, 30), Vector2(122, 82), Vector2(80, 125), Vector2(22, 110),
	Vector2(-18, 70), Vector2(-68, 115), Vector2(-120, 82), Vector2(-126, 10),
	Vector2(-88, -40), Vector2(-112, -95), Vector2(-55, -126),
]

const AUTUMN := [
	Color(1.0, 0.78, 0.12), Color(0.98, 0.66, 0.1), Color(0.97, 0.5, 0.12),
	Color(0.93, 0.36, 0.1), Color(0.88, 0.2, 0.14), Color(0.5, 0.75, 0.2),
]
const SPRUCE_GREENS := [Color(0.22, 0.42, 0.22), Color(0.28, 0.5, 0.25), Color(0.18, 0.36, 0.2)]

const GRASS_A := Color(0.24, 0.5, 0.19)
const GRASS_B := Color(0.38, 0.62, 0.23)
const DIRT := Color(0.55, 0.45, 0.32)
const SAND := Color(0.78, 0.72, 0.52)
const CLIFF := Color(0.5, 0.5, 0.46)
const ASPHALT := Color(0.46, 0.46, 0.48)
const LINE := Color(0.92, 0.92, 0.9)

@export var seed := 1337
@export var terrain_size := 400.0
@export var cell_size := 2.0
@export var hill_height := 14.0
@export var road_width := 8.0
@export var lake_center := Vector2(40, 0)
@export var lake_radius := 35.0
@export_range(0.0, 2.0) var tree_density := 1.0
## Carro posicionado no início da estrada ao rodar o jogo.
@export var car: Node3D
@export_tool_button("Regenerar", "Reload") var regenerate_action := regenerate

var _height_noise := FastNoiseLite.new()
var _detail_noise := FastNoiseLite.new()
var _forest_noise := FastNoiseLite.new()
var _n := 0
var _heights := PackedFloat32Array()
var _road_dist := PackedFloat32Array()
var _road_h := PackedFloat32Array()
var _road_pts := PackedVector3Array()
var _road_dirs := PackedVector3Array()
var _water_y := 0.0
var _lake_floor_h := 0.0
var _generated: Node3D
var _materials := {}


func _ready() -> void:
	regenerate()
	if not Engine.is_editor_hint() and car:
		_place_car()


func regenerate() -> void:
	if _generated:
		remove_child(_generated)
		_generated.queue_free()
	_generated = Node3D.new()
	_generated.name = "Generated"
	add_child(_generated)

	_setup_noise()
	_build_road_samples()
	_build_heights()
	_build_terrain()
	_build_road()
	_build_water()
	_scatter()


func _setup_noise() -> void:
	_height_noise.seed = seed
	_height_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_height_noise.frequency = 0.006
	_height_noise.fractal_octaves = 4
	_detail_noise.seed = seed + 1
	_detail_noise.frequency = 0.04
	_forest_noise.seed = seed + 2
	_forest_noise.frequency = 0.012
	_lake_floor_h = _height_noise.get_noise_2d(lake_center.x, lake_center.y) * hill_height
	_water_y = _lake_floor_h - 1.4


func _base_height(x: float, z: float) -> float:
	var h := _height_noise.get_noise_2d(x, z) * hill_height
	# Borda do mapa sobe para fechar o horizonte.
	h += smoothstep(150.0, 200.0, Vector2(x, z).length()) * 20.0
	# Lago: aplaina a margem na altura do centro e cava o meio.
	var ld := Vector2(x, z).distance_to(lake_center)
	h = lerpf(_lake_floor_h, h, smoothstep(lake_radius, lake_radius * 1.6, ld))
	h -= (1.0 - smoothstep(lake_radius * 0.3, lake_radius, ld)) * 5.0
	return h


func _build_road_samples() -> void:
	var curve := Curve3D.new()
	curve.bake_interval = 0.5
	var count := ROAD_POINTS.size()
	for i in count + 1:
		var p: Vector2 = ROAD_POINTS[i % count]
		var prev: Vector2 = ROAD_POINTS[(i - 1 + count) % count]
		var next: Vector2 = ROAD_POINTS[(i + 1) % count]
		var t := (next - prev) / 6.0  # Catmull-Rom -> Bézier
		curve.add_point(Vector3(p.x, 0, p.y), Vector3(-t.x, 0, -t.y), Vector3(t.x, 0, t.y))

	var length := curve.get_baked_length()
	var n := int(length)  # uma amostra por metro
	_road_pts.resize(n)
	for i in n:
		var p := curve.sample_baked(i * length / n)
		p.y = _base_height(p.x, p.z)
		_road_pts[i] = p

	# Suaviza a altura da estrada para rampas suaves (média móvel circular).
	for pass_i in 4:
		var smoothed := PackedFloat32Array()
		smoothed.resize(n)
		var w := 20
		for i in n:
			var acc := 0.0
			for k in range(-w, w + 1):
				acc += _road_pts[(i + k + n) % n].y
			smoothed[i] = acc / (w * 2 + 1)
		for i in n:
			_road_pts[i].y = smoothed[i]

	_road_dirs.resize(n)
	for i in n:
		var d := _road_pts[(i + 1) % n] - _road_pts[(i - 1 + n) % n]
		d.y = 0
		_road_dirs[i] = d.normalized()


func _build_heights() -> void:
	_n = int(terrain_size / cell_size) + 1
	var half := terrain_size * 0.5
	_heights.resize(_n * _n)
	_road_dist.resize(_n * _n)
	_road_h.resize(_n * _n)
	_road_dist.fill(INF)
	for z in _n:
		for x in _n:
			_heights[z * _n + x] = _base_height(-half + x * cell_size, -half + z * cell_size)

	# Carimba a distância até a estrada em cada vértice próximo.
	var reach := road_width * 0.5 + 20.0
	var rc := int(ceil(reach / cell_size))
	for p in _road_pts:
		var cx := int(round((p.x + half) / cell_size))
		var cz := int(round((p.z + half) / cell_size))
		for gz in range(maxi(cz - rc, 0), mini(cz + rc + 1, _n)):
			for gx in range(maxi(cx - rc, 0), mini(cx + rc + 1, _n)):
				var d := Vector2(-half + gx * cell_size - p.x, -half + gz * cell_size - p.z).length()
				var idx := gz * _n + gx
				if d < _road_dist[idx]:
					_road_dist[idx] = d
					_road_h[idx] = p.y

	# Aplaina o terreno sob a estrada e mistura com as encostas.
	for i in _heights.size():
		var d := _road_dist[i]
		if d < reach:
			var t := smoothstep(road_width * 0.5 + 1.5, reach, d)
			_heights[i] = lerpf(_road_h[i] - 0.3, _heights[i], t)


func _grid_h(x: int, z: int) -> float:
	return _heights[clampi(z, 0, _n - 1) * _n + clampi(x, 0, _n - 1)]


func _height_at(x: float, z: float) -> float:
	var half := terrain_size * 0.5
	var fx := clampf((x + half) / cell_size, 0.0, _n - 1.001)
	var fz := clampf((z + half) / cell_size, 0.0, _n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var a := lerpf(_grid_h(ix, iz), _grid_h(ix + 1, iz), tx)
	var b := lerpf(_grid_h(ix, iz + 1), _grid_h(ix + 1, iz + 1), tx)
	return lerpf(a, b, tz)


func _normal_at_grid(x: int, z: int) -> Vector3:
	return Vector3(
		_grid_h(x - 1, z) - _grid_h(x + 1, z),
		2.0 * cell_size,
		_grid_h(x, z - 1) - _grid_h(x, z + 1)).normalized()


func _road_dist_at(x: float, z: float) -> float:
	var half := terrain_size * 0.5
	var ix := clampi(int(round((x + half) / cell_size)), 0, _n - 1)
	var iz := clampi(int(round((z + half) / cell_size)), 0, _n - 1)
	return _road_dist[iz * _n + ix]


func _build_terrain() -> void:
	var half := terrain_size * 0.5
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	verts.resize(_n * _n)
	normals.resize(_n * _n)
	colors.resize(_n * _n)
	var hw := road_width * 0.5

	for z in _n:
		for x in _n:
			var i := z * _n + x
			var wx := -half + x * cell_size
			var wz := -half + z * cell_size
			var h := _heights[i]
			var nrm := _normal_at_grid(x, z)
			verts[i] = Vector3(wx, h, wz)
			normals[i] = nrm

			var c := GRASS_A.lerp(GRASS_B, _detail_noise.get_noise_2d(wx, wz) * 0.5 + 0.5)
			c = c.lerp(CLIFF, smoothstep(0.18, 0.35, 1.0 - nrm.y))
			var near_lake := 1.0 - smoothstep(lake_radius * 1.1, lake_radius * 1.4, Vector2(wx, wz).distance_to(lake_center))
			c = c.lerp(SAND, smoothstep(_water_y + 1.2, _water_y + 0.2, h) * near_lake)
			c = c.lerp(DIRT, smoothstep(hw + 3.5, hw + 1.0, _road_dist[i]))
			colors[i] = c

	for z in _n - 1:
		for x in _n - 1:
			var a := z * _n + x
			var b := a + 1
			var c := a + _n
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _terrain_material())

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	_generated.add_child(mi)
	_add_static_collision("TerrainCollision", mesh)


func _terrain_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/levels/landscape_art_test/terrain.gdshader")
	var noise_tex := NoiseTexture2D.new()
	noise_tex.seamless = true
	noise_tex.width = 256
	noise_tex.height = 256
	var fnl := FastNoiseLite.new()
	fnl.frequency = 0.05
	noise_tex.noise = fnl
	mat.set_shader_parameter("detail_noise", noise_tex)
	return mat


func _build_road() -> void:
	var hw := road_width * 0.5
	# [offset_ini, altura_ini, offset_fim, altura_fim, cor]
	var strips := [
		[-hw - 1.4, -0.25, -hw, 0.03, DIRT],
		[-hw, 0.06, -hw + 0.25, 0.06, LINE],
		[-hw + 0.25, 0.03, hw - 0.25, 0.03, ASPHALT],
		[hw - 0.25, 0.06, hw, 0.06, LINE],
		[hw, 0.03, hw + 1.4, -0.25, DIRT],
	]
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var n := _road_pts.size()

	for strip in strips:
		var base := verts.size()
		for i in n + 1:
			var k := i % n
			var p := _road_pts[k]
			var dir := _road_dirs[k]
			var side := Vector3(-dir.z, 0, dir.x)
			var col: Color = strip[4]
			if col == ASPHALT:
				col = col.lerp(Color(0.4, 0.4, 0.42), _detail_noise.get_noise_2d(p.x * 3.0, p.z * 3.0) * 0.5 + 0.5)
			verts.append(p + side * strip[0] + Vector3.UP * strip[1])
			verts.append(p + side * strip[2] + Vector3.UP * strip[3])
			normals.append_array([Vector3.UP, Vector3.UP])
			colors.append_array([col, col])
		for i in n:
			var a := base + i * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.85
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)

	var mi := MeshInstance3D.new()
	mi.name = "Road"
	mi.mesh = mesh
	_generated.add_child(mi)
	_add_static_collision("RoadCollision", mesh)

	# Balizas brancas nas laterais, a cada 24 m.
	var posts: Array[Transform3D] = []
	for i in range(0, n, 24):
		var p := _road_pts[i]
		var side := Vector3(-_road_dirs[i].z, 0, _road_dirs[i].x)
		for s in [-1.0, 1.0]:
			var pos: Vector3 = p + side * s * (hw + 2.0) + Vector3.UP * 0.25
			posts.append(Transform3D(Basis(), pos))
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.14, 1.0, 0.14)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.95, 0.95, 0.92)
	post_mesh.material = post_mat
	_add_multimesh("RoadPosts", post_mesh, posts, [])


func _build_water() -> void:
	var disc := CylinderMesh.new()
	disc.top_radius = lake_radius * 1.08
	disc.bottom_radius = lake_radius * 1.08
	disc.height = 0.05
	disc.radial_segments = 64
	disc.rings = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.74, 0.84)
	mat.roughness = 0.15
	mat.metallic_specular = 0.6
	disc.material = mat
	var mi := MeshInstance3D.new()
	mi.name = "Lake"
	mi.mesh = disc
	mi.position = Vector3(lake_center.x, _water_y, lake_center.y)
	_generated.add_child(mi)


func _scatter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var oaks := _load_variants(OAKS)
	var spruces := _load_variants(SPRUCES)
	var deads := _load_variants(DEAD_TREES)
	var rocks := _load_variants(ROCKS)
	var big_rocks := _load_variants(BIG_ROCKS)

	# bucket por variante: [transforms, cores]
	var buckets := {}
	var tree_spots: Array[Vector3] = []
	var rock_shapes: Array = []  # [transform, shape]

	var spacing := 5.0
	var half := terrain_size * 0.5 - 4.0
	var steps := int(half * 2.0 / spacing)
	var hw := road_width * 0.5

	for gz in steps:
		for gx in steps:
			var x := -half + gx * spacing + rng.randf_range(-2.0, 2.0)
			var z := -half + gz * spacing + rng.randf_range(-2.0, 2.0)
			var d := _road_dist_at(x, z)
			if d < hw + 3.5:
				continue
			if Vector2(x, z).distance_to(lake_center) < lake_radius * 1.05:
				continue
			var y := _height_at(x, z)
			var forest := _forest_noise.get_noise_2d(x, z) * 0.5 + 0.5
			# Estrada ladeada de árvores, como nos estágios do art of rally.
			var road_bonus := 0.4 * (1.0 - smoothstep(6.0, 22.0, d))
			var p_tree := (smoothstep(0.35, 0.65, forest) + road_bonus) * 0.8 * tree_density
			var roll := rng.randf()
			var yaw := Basis(Vector3.UP, rng.randf() * TAU)

			if roll < p_tree:
				var kind := rng.randf()
				var variant: Dictionary
				var color: Color
				var target_h: float
				if kind < 0.05:
					variant = deads[rng.randi() % deads.size()]
					color = Color.WHITE
					target_h = rng.randf_range(6.0, 9.0)
				elif kind < 0.05 + 0.3 * forest:
					variant = spruces[rng.randi() % spruces.size()]
					color = SPRUCE_GREENS[rng.randi() % SPRUCE_GREENS.size()]
					target_h = rng.randf_range(7.0, 11.0)
				else:
					variant = oaks[rng.randi() % oaks.size()]
					color = AUTUMN[rng.randi() % AUTUMN.size()]
					color = color.lightened(rng.randf_range(-0.05, 0.1))
					target_h = rng.randf_range(6.0, 9.0)
				var s: float = target_h / variant.size.y
				var xf := Transform3D(yaw.scaled(Vector3.ONE * s), Vector3(x, y - 0.3, z))
				_bucket_add(buckets, variant, xf, color)
				tree_spots.append(Vector3(x, y, z))
			elif roll < p_tree + 0.04 + 0.06 * (1.0 - smoothstep(5.0, 15.0, d)):
				var variant: Dictionary = rocks[rng.randi() % rocks.size()]
				var target := rng.randf_range(0.5, 1.8)
				var s: float = target / maxf(variant.size.x, variant.size.z)
				var xf := Transform3D(yaw.scaled(Vector3.ONE * s), Vector3(x, y - variant.size.y * s * 0.25, z))
				_bucket_add(buckets, variant, xf, _rock_tint(rng))
				rock_shapes.append([xf, variant.shape])

	# Rochas grandes nas colinas, longe da pista.
	var placed := 0
	var attempts := 0
	while placed < 28 and attempts < 500:
		attempts += 1
		var x := rng.randf_range(-half, half)
		var z := rng.randf_range(-half, half)
		if _road_dist_at(x, z) < hw + 10.0 or Vector2(x, z).distance_to(lake_center) < lake_radius * 1.2:
			continue
		var variant: Dictionary = big_rocks[rng.randi() % big_rocks.size()]
		var target := rng.randf_range(4.0, 9.0)
		var s: float = target / maxf(variant.size.x, variant.size.z)
		var y: float = _height_at(x, z) - variant.size.y * s * 0.3
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y, z))
		_bucket_add(buckets, variant, xf, _rock_tint(rng))
		rock_shapes.append([xf, variant.shape])
		placed += 1

	for mesh in buckets:
		var b: Array = buckets[mesh]
		_add_multimesh("Scatter", mesh, b[0], b[1])

	_add_scatter_collision(tree_spots, rock_shapes)


func _rock_tint(rng: RandomNumberGenerator) -> Color:
	var v := rng.randf_range(0.8, 1.05)
	return Color(v, v * 0.98, v * 0.94)


func _bucket_add(buckets: Dictionary, variant: Dictionary, xf: Transform3D, color: Color) -> void:
	var mesh: Mesh = variant.mesh
	if not buckets.has(mesh):
		var xforms: Array[Transform3D] = []
		buckets[mesh] = [xforms, []]
	buckets[mesh][0].append(xf)
	buckets[mesh][1].append(color)


func _add_multimesh(node_name: String, mesh: Mesh, xforms: Array[Transform3D], colors: Array) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	_generated.add_child(mmi)


func _add_static_collision(node_name: String, mesh: Mesh) -> void:
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = node_name
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	_generated.add_child(body)


func _add_scatter_collision(tree_spots: Array[Vector3], rock_shapes: Array) -> void:
	var body := StaticBody3D.new()
	body.name = "ScatterCollision"
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.35
	trunk.height = 6.0
	for p in tree_spots:
		var cs := CollisionShape3D.new()
		cs.shape = trunk
		cs.position = p + Vector3.UP * 2.5
		body.add_child(cs)
	for entry in rock_shapes:
		var cs := CollisionShape3D.new()
		cs.shape = entry[1]
		cs.transform = entry[0]
		body.add_child(cs)
	_generated.add_child(body)


## Carrega os FBX e devolve malhas "limpas": pivô na base, centradas,
## escala/rotação do FBX aplicadas e materiais estilizados.
func _load_variants(paths: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path in paths:
		var root: Node = (load(path) as PackedScene).instantiate()
		var mi := _find_mesh_instance(root)
		var xf := Transform3D()
		var node: Node = mi
		while node != root:
			xf = (node as Node3D).transform * xf
			node = node.get_parent()
		var src := mi.mesh
		var aabb := xf * src.get_aabb()
		var center := aabb.get_center()
		var full := Transform3D(Basis(), Vector3(-center.x, -aabb.position.y, -center.z)) * xf
		var nbasis := full.basis.inverse().transposed()

		var mesh := ArrayMesh.new()
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] = full * verts[i]
			for i in norms.size():
				norms[i] = (nbasis * norms[i]).normalized()
			var clean := []
			clean.resize(Mesh.ARRAY_MAX)
			clean[Mesh.ARRAY_VERTEX] = verts
			clean[Mesh.ARRAY_NORMAL] = norms
			clean[Mesh.ARRAY_TEX_UV] = arrays[Mesh.ARRAY_TEX_UV]
			clean[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, clean)
			var src_mat := mi.get_active_material(s)
			mesh.surface_set_material(s, _material_for(src_mat.resource_name if src_mat else ""))

		out.append({
			"mesh": mesh,
			"size": aabb.size,
			"shape": mesh.create_convex_shape(true, true),
		})
		root.free()
	return out


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null


func _material_for(mat_name: String) -> Material:
	if _materials.has(mat_name):
		return _materials[mat_name]
	var mat := StandardMaterial3D.new()
	mat.roughness = 1.0
	if "Leaf" in mat_name:
		# Cor vem da instância (paleta de outono / verdes).
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif mat_name == "OakTreeTrunk":
		mat.albedo_color = Color(0.86, 0.84, 0.8)  # tronco claro, tipo bétula
	elif "Dead" in mat_name:
		mat.albedo_color = Color(0.48, 0.4, 0.34)
	elif "Trunk" in mat_name:
		mat.albedo_color = Color(0.4, 0.29, 0.21)
	else:
		mat.vertex_color_use_as_albedo = true
		mat.vertex_color_is_srgb = true
		mat.albedo_color = Color(0.62, 0.61, 0.58)
		mat.roughness = 0.9
	_materials[mat_name] = mat
	return mat


func _place_car() -> void:
	var p := _road_pts[0]
	var dir := _road_dirs[0]
	car.global_transform = Transform3D(Basis.looking_at(dir, Vector3.UP, true), p + Vector3.UP * 1.0)
