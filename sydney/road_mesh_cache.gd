class_name RoadMeshCacheData
extends Resource

## Disk cache for SydneyWorld._build_roads()'s three generated meshes (surface
## ribbon, tunnel surface, tunnel shell) — deterministic for a given export
## file, same pattern as CbdBuildingCacheData (see
## docs/PERFORMANCE_AUDIT_2026-11-24.md §10). Tunnel portal frames are cheap
## node-tree construction and are rebuilt every run rather than cached here.

@export var roads_mesh: Mesh
@export var roads_vertices: int = 0
@export var roads_triangles: int = 0
@export var tunnel_surface_mesh: Mesh
@export var tunnel_surface_vertices: int = 0
@export var tunnel_surface_triangles: int = 0
@export var tunnel_shell_mesh: Mesh
@export var tunnel_shell_vertices: int = 0
@export var tunnel_shell_triangles: int = 0
