class_name RoofLayer
extends Node2D
## Toits des bâtiments de SURFACE (jalon 8), dessinés au-dessus des entités et sous le brouillard (z_index 4).
## Chaque chunk connaît l'empreinte de son bâtiment (`Chunk.roof`, calculée par `build_roof()`) : les murs et l'intérieur
## sont couverts, les portes et fenêtres restent visibles. Un toit n'apparaît qu'une fois le bâtiment aperçu
## (`Chunk.roof_known`) ; le brouillard gère ensuite les cases vues / mémorisées / inconnues.
## Le toit du bâtiment où se trouve le joueur est masqué (`World.roof_hidden_chunk`) : on voit alors l'intérieur.
## Pendant l'aperçu d'un autre étage (LookUI), aucun toit n'est masqué : le joueur n'est pas réellement dans le bâtiment.

var world: World


func _draw() -> void:
	if world == null or world.get_level() != 0:
		return
	for key: Vector3i in world.chunks.chunks:
		if key.z != 0:
			continue
		var chunk := world.chunks.chunks[key] as Chunk
		if chunk == null or not chunk.roof_known or chunk.roof.size() != Chunk.CELLS:
			continue
		if chunk.key == world.roof_hidden_chunk:
			continue
		for i in Chunk.CELLS:
			if chunk.roof[i] != Chunk.ROOF_COVER:
				continue
			var cell: Vector2i = chunk.cell_of(i)
			UlticaTiles.draw_sprite(self, world.chunks.roof_sprite(cell), Vector2(cell * World.TILE_SIZE))
