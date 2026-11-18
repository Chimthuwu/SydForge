# District Zero design baseline

Source: the user's BOOMTOWN first-deliverable brief. No earlier project
specification or finalized design was supplied in the repository. The following
are prototype choices, not attributed to a missing specification.

Third-person arcade action in a bright, exaggerated urban district. The loop is
walk, sprint and jump; find a vehicle; drive; exit; fight; recover after defeat.
One metre is one Godot unit. The playable district spans approximately 220 m,
with 18 m avenues, full intersections, pedestrian crossings and raised sidewalks.
The city includes a landscaped park, fountain, rocket monument, diner, hotel,
arcade, record shop, garage, civic hall and perimeter skyline.

Vehicles: Comet coupe (balanced), Viper sports car (fast, fragile), Hauler van
(slow, durable), Sunbeam taxi (moderate speed and handling). All share a custom
CharacterBody3D drivetrain, acceleration, reverse, speed-dependent steering,
lateral grip, braking and collision damage. This is not a realistic simulator.

Combat: camera-centred hitscan pistol, 12-round magazine, 1.25 second reload,
25 damage; short-range melee, 40 damage; enemy has 100 health. Player has 100
health and respawns at the start with three seconds of invulnerability. Enemy
line of sight gates ranged attacks. Reputation counts defeated enemies.

Original procedural low-poly geometry is the art baseline. No external art or
licensing assumptions. The 4 × 4 km city, missions, traffic, police, interiors,
save system and advanced character animation are outside this milestone.
