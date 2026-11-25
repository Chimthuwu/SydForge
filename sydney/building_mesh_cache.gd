class_name BuildingMeshCacheData
extends Resource

## Disk cache for SydneyWorld._build_buildings()'s heavy output: merging
## ~19k building footprints into one mesh + collision shape costs ~16 s of
## pure GDScript geometry math (see docs/PERFORMANCE_AUDIT_2026-11-24.md §8),
## and the result is fully deterministic for a given export file. Cached
## under user://cache/, keyed by a hash of the export JSON text, so repeat
## launches with an unchanged city skip straight to this.

@export var mesh: Mesh
@export var shape: Shape3D
@export var collision_triangles: int = 0
@export var built: int = 0
@export var skipped: int = 0
@export var degenerate_triangles: int = 0
@export var vertices: int = 0
@export var triangles: int = 0
