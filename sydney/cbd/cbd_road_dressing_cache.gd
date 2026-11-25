class_name CbdRoadDressingCacheData
extends Resource

## Disk cache for CbdWorld._build_roads()'s CBD-specific lane-marking and
## kerb meshes, same pattern as RoadMeshCacheData/CbdBuildingCacheData.

@export var lane_markings_mesh: Mesh
@export var lane_markings_vertices: int = 0
@export var lane_markings_triangles: int = 0
@export var kerbs_mesh: Mesh
@export var kerbs_vertices: int = 0
@export var kerbs_triangles: int = 0
