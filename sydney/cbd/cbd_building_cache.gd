class_name CbdBuildingCacheData
extends Resource

## Disk cache for CbdWorld._build_buildings()'s output (CbdBuildings.build()):
## the per-building facade mesh, night-window mesh and collision shape for
## ~19k buildings, which is ~16 s of GDScript geometry/SurfaceTool work and
## fully deterministic for a given export file (see
## docs/PERFORMANCE_AUDIT_2026-11-24.md §8/§9). Cached under user://cache/,
## keyed by a hash of the export JSON text.

@export var mesh: Mesh
@export var night_windows: Mesh
@export var shape: Shape3D
@export var collision_triangles: int = 0
@export var stats: Dictionary = {}
