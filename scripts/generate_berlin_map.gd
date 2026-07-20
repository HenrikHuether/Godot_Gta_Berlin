extends SceneTree

const MAP_PATH = "res://scenes/BerlinMap.tscn"
const FACADE_PATH = "res://Assets/Textures/berlin_facade.png"

var map_root
var facade_materials = []
var asphalt_material
var sidewalk_material
var grass_material
var roof_material
var stone_material
var metal_material
var glass_material

func _init():
	map_root = Spatial.new()
	map_root.name = "BerlinMap"
	build_materials()
	build_ground_and_roads()
	build_city_blocks()
	build_brandenburg_gate()
	build_television_tower()
	build_street_furniture()
	var packed = PackedScene.new()
	var result = packed.pack(map_root)
	if result == OK:
		result = ResourceSaver.save(MAP_PATH, packed)
	if result != OK:
		printerr("BerlinMap could not be saved: ", result)
		quit(1)
	else:
		print("Saved detailed Berlin map to ", MAP_PATH)
		quit()

func make_material(color: Color, texture = null, uv_scale := Vector3.ONE):
	var mat = SpatialMaterial.new()
	mat.albedo_color = color
	mat.roughness = 0.86
	if texture:
		mat.albedo_texture = texture
		mat.uv1_scale = uv_scale
	return mat

func make_pattern_texture(kind: String):
	var image = Image.new()
	image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.lock()
	for y in range(128):
		for x in range(128):
			var noise = fmod(float((x * 17 + y * 31 + x * y * 3) % 101) / 100.0, 1.0)
			var color = Color.white
			if kind == "asphalt":
				var value = 0.13 + noise * 0.055
				color = Color(value, value * 1.03, value * 1.08)
			elif kind == "sidewalk":
				var joint = x % 32 < 2 or y % 16 < 2 or ((y / 16) % 2 == 1 and (x + 16) % 32 < 2)
				color = Color("686a6c") if joint else Color(0.48 + noise * 0.05, 0.47 + noise * 0.05, 0.44 + noise * 0.05)
			elif kind == "grass":
				color = Color(0.17 + noise * 0.07, 0.32 + noise * 0.10, 0.15 + noise * 0.05)
			else:
				var joint = x % 24 < 2 or y % 12 < 2
				color = Color("4d2924") if joint else Color(0.30 + noise * 0.08, 0.12 + noise * 0.035, 0.09 + noise * 0.025)
			image.set_pixel(x, y, color)
	image.unlock()
	var texture = ImageTexture.new()
	texture.create_from_image(image, Texture.FLAG_REPEAT | Texture.FLAG_MIPMAPS)
	return texture

func build_materials():
	var facade_texture = load(FACADE_PATH)
	for tint in [Color("f3e3cb"), Color("e5c6a3"), Color("d9d2c4"), Color("d6b39a"), Color("e6d69e")]:
		facade_materials.append(make_material(tint, facade_texture))
	asphalt_material = make_material(Color.white, make_pattern_texture("asphalt"), Vector3(18, 18, 18))
	sidewalk_material = make_material(Color.white, make_pattern_texture("sidewalk"), Vector3(10, 10, 10))
	grass_material = make_material(Color.white, make_pattern_texture("grass"), Vector3(22, 22, 22))
	roof_material = make_material(Color.white, make_pattern_texture("roof"), Vector3(5, 5, 5))
	stone_material = make_material(Color("c9b58f"))
	metal_material = make_material(Color("26292b"))
	metal_material.metallic = 0.55
	glass_material = make_material(Color("28434e"))
	glass_material.metallic = 0.25
	glass_material.roughness = 0.18

func own(node):
	node.owner = map_root
	return node

func add_box(parent: Node, node_name: String, position: Vector3, size: Vector3, mat, collision := false):
	var container
	if collision:
		container = StaticBody.new()
		container.name = node_name
		container.translation = position
		parent.add_child(container)
		own(container)
	else:
		container = Spatial.new()
		container.name = node_name
		container.translation = position
		parent.add_child(container)
		own(container)
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = "Mesh"
	var mesh = CubeMesh.new()
	mesh.size = size
	mesh.material = mat
	mesh_instance.mesh = mesh
	container.add_child(mesh_instance)
	own(mesh_instance)
	if collision:
		var collision_shape = CollisionShape.new()
		collision_shape.name = "CollisionShape"
		var shape = BoxShape.new()
		shape.extents = size * 0.5
		collision_shape.shape = shape
		container.add_child(collision_shape)
		own(collision_shape)
	return container

func add_cylinder(parent: Node, node_name: String, position: Vector3, radius: float, height: float, mat, collision := false):
	var container = StaticBody.new() if collision else Spatial.new()
	container.name = node_name
	container.translation = position
	parent.add_child(container)
	own(container)
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = "Mesh"
	var mesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.material = mat
	mesh_instance.mesh = mesh
	container.add_child(mesh_instance)
	own(mesh_instance)
	if collision:
		var collision_shape = CollisionShape.new()
		var shape = CylinderShape.new()
		shape.radius = radius
		shape.height = height
		collision_shape.shape = shape
		container.add_child(collision_shape)
		own(collision_shape)
	return container

func add_sphere(parent: Node, node_name: String, position: Vector3, radius: float, mat):
	var mesh_instance = MeshInstance.new()
	mesh_instance.name = node_name
	mesh_instance.translation = position
	var mesh = SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = mat
	mesh_instance.mesh = mesh
	parent.add_child(mesh_instance)
	own(mesh_instance)
	return mesh_instance

func build_ground_and_roads():
	add_box(map_root, "Ground", Vector3(0, -0.20, 0), Vector3(520, 0.4, 520), grass_material, true)
	var road_positions = [-180, -90, 0, 90, 180]
	for axis_position in road_positions:
		add_box(map_root, "Road_X_%d" % axis_position, Vector3(0, 0.025, axis_position), Vector3(520, 0.05, 16), asphalt_material)
		add_box(map_root, "Road_Z_%d" % axis_position, Vector3(axis_position, 0.03, 0), Vector3(16, 0.06, 520), asphalt_material)
		for marker in range(-250, 251, 12):
			add_box(map_root, "LaneMark", Vector3(marker, 0.065, axis_position), Vector3(5.0, 0.025, 0.18), make_material(Color("ece6c8")))
			add_box(map_root, "LaneMark", Vector3(axis_position, 0.07, marker), Vector3(0.18, 0.025, 5.0), make_material(Color("ece6c8")))
	for x in road_positions:
		for z in road_positions:
			for stripe in [-5.0, -2.5, 0.0, 2.5, 5.0]:
				add_box(map_root, "Crosswalk", Vector3(x + stripe, 0.085, z - 10.0), Vector3(1.2, 0.025, 5.0), make_material(Color("e9e9e4")))

func build_city_blocks():
	var block_centers = [-135, -45, 45, 135]
	var block_index = 0
	for center_x in block_centers:
		for center_z in block_centers:
			var block = Spatial.new()
			block.name = "Block_%02d" % block_index
			map_root.add_child(block)
			own(block)
			add_box(block, "Sidewalk", Vector3(center_x, 0.10, center_z), Vector3(74, 0.20, 74), sidewalk_material, true)
			add_box(block, "Courtyard", Vector3(center_x, 0.225, center_z), Vector3(34, 0.05, 34), grass_material)
			var building_index = 0
			for offset in [-24, 0, 24]:
				add_building(block, block_index, building_index, Vector3(center_x + offset, 0.20, center_z - 27), Vector3(22, 0, 16), Vector3(0, 0, -1))
				building_index += 1
				add_building(block, block_index, building_index, Vector3(center_x + offset, 0.20, center_z + 27), Vector3(22, 0, 16), Vector3(0, 0, 1))
				building_index += 1
			for offset in [-14, 14]:
				add_building(block, block_index, building_index, Vector3(center_x - 27, 0.20, center_z + offset), Vector3(16, 0, 22), Vector3(-1, 0, 0))
				building_index += 1
				add_building(block, block_index, building_index, Vector3(center_x + 27, 0.20, center_z + offset), Vector3(16, 0, 22), Vector3(1, 0, 0))
				building_index += 1
			add_tree(block, Vector3(center_x - 9, 0.25, center_z))
			add_tree(block, Vector3(center_x + 9, 0.25, center_z))
			block_index += 1

func add_building(parent: Node, block_index: int, building_index: int, base_position: Vector3, footprint: Vector3, street_direction: Vector3):
	var height = 20.0 + float((block_index * 7 + building_index * 5) % 5) * 3.0
	var mat = facade_materials[(block_index + building_index) % facade_materials.size()]
	var building = add_box(parent, "Building_%02d_%02d" % [block_index, building_index], base_position + Vector3.UP * height * 0.5, Vector3(footprint.x, height, footprint.z), mat, true)
	add_box(building, "Roof", Vector3(0, height * 0.5 + 0.65, 0), Vector3(footprint.x + 0.8, 1.3, footprint.z + 0.8), roof_material)
	add_box(building, "Cornice", Vector3(street_direction.x * (footprint.x * 0.5 + 0.12), height * 0.36, street_direction.z * (footprint.z * 0.5 + 0.12)), Vector3(footprint.x + (0.35 if street_direction.z != 0 else 0.25), 0.45, footprint.z + (0.35 if street_direction.x != 0 else 0.25)), stone_material)
	var door_size = Vector3(2.2, 3.4, 0.18) if street_direction.z != 0 else Vector3(0.18, 3.4, 2.2)
	var door_position = Vector3(street_direction.x * (footprint.x * 0.5 + 0.10), -height * 0.5 + 1.7, street_direction.z * (footprint.z * 0.5 + 0.10))
	add_box(building, "Entrance", door_position, door_size, metal_material)

func add_tree(parent: Node, ground_position: Vector3):
	var tree = Spatial.new()
	tree.name = "Tree"
	tree.translation = ground_position
	parent.add_child(tree)
	own(tree)
	add_cylinder(tree, "Trunk", Vector3(0, 2.0, 0), 0.35, 4.0, make_material(Color("60422d")))
	add_sphere(tree, "Crown", Vector3(0, 5.2, 0), 2.5, make_material(Color("396b35")))

func build_brandenburg_gate():
	var gate = Spatial.new()
	gate.name = "BrandenburgGate"
	gate.translation = Vector3(-225, 0, 0)
	map_root.add_child(gate)
	own(gate)
	for x in [-9, -5.4, -1.8, 1.8, 5.4, 9]:
		add_cylinder(gate, "Column", Vector3(x, 6.0, 0), 0.75, 12.0, stone_material, true)
	add_box(gate, "Entablature", Vector3(0, 12.8, 0), Vector3(22, 2.0, 5.0), stone_material, true)
	add_box(gate, "Top", Vector3(0, 14.2, 0), Vector3(18, 0.8, 4.0), stone_material)

func build_television_tower():
	var tower = Spatial.new()
	tower.name = "Fernsehturm"
	tower.translation = Vector3(220, 0, 220)
	map_root.add_child(tower)
	own(tower)
	add_cylinder(tower, "Shaft", Vector3(0, 28, 0), 1.5, 56, stone_material, true)
	add_sphere(tower, "Sphere", Vector3(0, 58, 0), 5.5, metal_material)
	add_cylinder(tower, "Antenna", Vector3(0, 72, 0), 0.35, 24, metal_material)

func build_street_furniture():
	for x in range(-210, 211, 30):
		for z in [-188, -82, -8, 98, 172]:
			add_lamp(Vector3(x, 0, z))
	for z in range(-210, 211, 30):
		for x in [-172, -98, 8, 82, 188]:
			add_lamp(Vector3(x, 0, z))

func add_lamp(position: Vector3):
	var lamp = Spatial.new()
	lamp.name = "StreetLamp"
	lamp.translation = position
	map_root.add_child(lamp)
	own(lamp)
	add_cylinder(lamp, "Pole", Vector3(0, 3.0, 0), 0.12, 6.0, metal_material)
	add_sphere(lamp, "LightHousing", Vector3(0, 6.2, 0), 0.42, glass_material)
