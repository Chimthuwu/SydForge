# SydForge — Visual Capture Test Plan (L85)

**Purpose:** Human visual verification of 131 new storefronts, night headlights, and expanded pause/controls screens.

**Context:** Headless tests verify logic (`business_poi_test`, `vehicle_headlights_test`, `lighting_pause_test`, `settings_input_test`). Visual legibility, layout, lighting, and UX require human review.

---

## 1. Storefronts (131 POIs)

### Test Matrix

| Brand | Count | Locations to Check | Visual Checks |
|-------|-------|-------------------|---------------|
| McDonald's | 11 | George St, Pitt St, Parramatta Rd | Golden arches visible, sign lit at night |
| KFC | 7 | Haymarket, Kings Cross, Newtown | Colonel logo, red/white palette |
| 7-Eleven | 10 | Circular Quay, Central, Darlinghurst | Green/white/orange stripes, 24/7 sign |
| Woolworths | 16 | CBD, Surry Hills, Bondi Junction | Green "W" logo, fresh food imagery |
| Coles | 7 | Town Hall, Darling Harbour, Redfern | Red "Coles" script, curved logo |
| Independent | ~80 | Throughout districts | Unique signage, no duplicates |

### Visual Checklist per Storefront

- [ ] Sign visible from street (not occluded by trees/furniture)
- [ ] Sign readable at 20m (day) and 15m (night)
- [ ] Night lighting: sign emissive/illuminated
- [ ] Facade integration: sign sits on building surface, no z-fighting
- [ ] Heritage buildings: no chain signage (verified by `business_poi_test`)
- [ ] Parody retail clearance: 18m minimum from real POI
- [ ] Supermarket POIs (Woolworths/Coles) use supermarket system, not generic

### Camera Angles

- Street level (pedestrian view)
- Vehicle dashboard view (driving past)
- Aerial (menu viewpoint)
- Night vs day comparison

---

## 2. Night Headlights

### Vehicle Classes to Verify

| Class | Beam Count | Beam Pattern | Night Checks |
|-------|------------|--------------|--------------|
| Commuter (sedan/hatch) | 2 | Standard spread | ☐ |
| Sports (Comet, Viper) | 2 | Wider, brighter | ☐ |
| Supercar (Sting, Phantom, Apex) | 2 | Long throw, sharp cutoff | ☐ |
| Hauler (van/truck) | 2 | High mount, wide | ☐ |
| Motorbike | 1 | Central, round | ☐ |

### Headlight Checks

- [ ] F key toggles on/off (visual feedback immediate)
- [ ] Entering vehicle at night → auto-on
- [ ] Exiting vehicle → headlights off, on-foot torch on
- [ ] Beam reaches road surface 30m ahead
- [ ] No shadow casting (performance)
- [ ] Beam color: cool white (5500K-6500K)
- [ ] AI traffic headlights: max 6 nearest, player-exempt
- [ ] High beam / low beam distinction (if implemented)

### Night Scenarios

- [ ] CBD streets (George St, Pitt St) — dense traffic
- [ ] Arterials (Parramatta Rd) — high speed, sparse
- [ ] Harbour Bridge — long straight, bridge lighting
- [ ] Tunnels / underpasses — transition lighting
- [ ] Rain / wet roads — reflection on asphalt

---

## 3. Pause / Controls Screens

### Pause Menu Sections

| Section | Elements | Checks |
|---------|----------|--------|
| Resume | Button | ☐ Returns to game, unpauses |
| Respawn | Button | ☐ Kills player, respawns at spawn |
| Return to Menu | Button | ☐ Unloads world, shows main menu |
| Settings → Video | Fullscreen, VSync, Resolution | ☐ Changes apply immediately |
| Settings → Audio | Master, Music, SFX sliders | ☐ Volume changes audible |
| Settings → Input | Sensitivity, Invert-Y, Remap | ☐ Remap captures key, persists |
| Settings → Gameplay | AI headlight density | ☐ 0-10 slider, affects traffic |
| Controls Screen | Full binding list | ☐ All actions listed, remappable |

### Visual Checks

- [ ] Overlay background: semi-transparent, blurs game
- [ ] Text legible at 1080p and 4K
- [ ] Focus navigation (gamepad/keyboard) works
- [ ] ESC closes any sub-menu, returns to pause
- [ ] Settings persist across sessions (`user://settings.cfg`)
- [ ] No input bleed (game actions don't trigger while paused)

---

## Sign-Off

| Category | Item | Tester | Date | Build | Pass/Fail | Notes |
|----------|------|--------|------|-------|-----------|-------|
| Storefronts | McDonald's (11) | | | | | |
| Storefronts | KFC (7) | | | | | |
| Storefronts | 7-Eleven (10) | | | | | |
| Storefronts | Woolworths (16) | | | | | |
| Storefronts | Coles (7) | | | | | |
| Storefronts | Independent (80) | | | | | |
| Headlights | Commuter | | | | | |
| Headlights | Sports | | | | | |
| Headlights | Supercar | | | | | |
| Headlights | Hauler | | | | | |
| Headlights | Motorbike | | | | | |
| Headlights | AI budget (6) | | | | | |
| Pause | All sections | | | | | |
| Controls | All bindings | | | | | |
| Persistence | Settings reload | | | | | |

---

## Related Files

- `sydney/cbd/cbd_businesses.gd` — POI placement, facade snapping
- `sydney/world/businesses.json` — 189 POIs, ODbL attribution
- `scripts/vehicle.gd` — headlight beams, toggle logic
- `scripts/city_lights_manager.gd` — AI headlight budget (6 nearest)
- `scripts/pause_menu.gd` — overlay, sections, navigation
- `scripts/game_settings.gd` — persistence, remap, sensitivity
- `tests/business_poi_test.gd` — 20/0 headless
- `tests/vehicle_headlights_test.gd` — 32/0 headless
- `tests/lighting_pause_test.gd` — 17/0 headless
- `tests/settings_input_test.gd` — 12/0 headless