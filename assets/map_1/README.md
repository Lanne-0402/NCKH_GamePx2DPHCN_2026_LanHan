# Map 1 curated assets

Map 1 uses one primary visual family: **Legacy Fantasy - High Forest 2.3**.
The UI frames come from **Kenney Pixel UI Pack (CC0)**.

## Ready and in use

| File | Purpose | Original source |
| --- | --- | --- |
| `environment/background_sky.png` | Static sky layer | `Legacy-Fantasy - High Forest 2.3/Background/Background.png` |
| `environment/forest_far.png` | Repeating distant forest layer | `Legacy-Fantasy - High Forest 2.3/Trees/Background.png` |
| `environment/forest_near.png` | Repeating foreground bushes | `Legacy-Fantasy - High Forest 2.3/Assets/Tree-Assets.png` |
| `environment/ground_grass_tile.png` | Ground surface tile | `Legacy-Fantasy - High Forest 2.3/Assets/Tiles.png` |
| `environment/ground_rock_tile.png` | Ground fill tile | `Legacy-Fantasy - High Forest 2.3/Assets/Tiles.png` |
| `obstacles/rock_base.png` | Map 1 obstacle | `Legacy-Fantasy - High Forest 2.3/Assets/Props-Rocks.png` |
| `goal/cave_entrance.png` | End-of-map cave entrance | `Legacy-Fantasy - High Forest 2.3/Assets/Tree-Assets.png` |
| `ui/*.png`, `ui/map1_theme.tres` | Instruction/result panel and button frames | `kenney_pixel-ui-pack/9-Slice/Ancient` |

The exported images are cropped copies. Keep the original packs unchanged when
creating further variants.

> License checkpoint: the repository currently contains the Kenney CC0 license,
> but no separate license file for the High Forest pack. Verify and archive its
> original itch.io license before distributing a public or commercial build.

## Waiting for replacement assets

- `characters/`: front-readable rehabilitation character with `idle`, `run`,
  `exercise`, `tracking_lost`, and `finish` animations.
- `pose_guide/`: start/end illustration for scapular retraction, with both
  elbows visibly bent at 90 degrees.
- `effects/`: dedicated rock crack and break animation.
- `audio/`: ambient forest loop, approach cue, correct-repetition cue, rock
  break sound, rest cue, and completion cue.

Until those assets are available, Map 1 keeps its existing functional
placeholder behavior. Do not substitute sword attacks for the rehabilitation
movement because that would communicate the wrong pose to the player.

## Import rules

- Use nearest-neighbor filtering for pixel art.
- Keep sprite scale on whole-number steps where possible.
- Use bottom-center pivots for the player, obstacle, and cave.
- Gameplay collision remains independent from visual sprite bounds.
