# Troubleshooting decision tree

Use these branches for an actual reported symptom or production error. Default completion ends with the user's own visual/game verification; do not start a diagnostic suite, Blender pose renders, HLMV or GMod acceptance automatically. Keep production error handling within the affected operation. Follow [prerequisites.md](prerequisites.md) for the user's installation choice when a required tool is truly missing.

## Model is giant or tiny

Check SMD bounds before QC. A Source human is roughly 72 units tall. Confirm Blender unit/export scale, applied mesh transforms, armature object scale, and axis conversion. Do not use QC `$scale` to hide inconsistent mesh and skeleton units.

## Model explodes, becomes spikes, or limbs fly away

This is almost always a bind-space/skeleton contract failure:

- candidate and animation skeletons have different parents or frame-0 transforms;
- node IDs were replaced but vertex weight IDs were not remapped;
- weights point to nonexistent IDs;
- armature or mesh transforms were applied after binding;
- custom rest bones were paired with canonical animations without a real retarget.

For this actual bind-space problem, use `validate_smd.py` against the exact classic reference when helpful. Return to the Blender checkpoint before export; do not try to repair this with Lua, model scale, or material changes. First-person hands require reference-derived height bounds rather than the default full-human range.

## Model is visible but twisted in every animation

The mesh may look correct in rest pose while the armature differs from the classic bind pose. Compare bone-by-bone parent and transform data. Rebind the mesh to the imported canonical armature instead of copying bone names onto the custom armature.

## Neck stretches, collapses, or tears

Inspect head/neck/spine weight gradients and duplicate vertices at the seam. A rigid head can follow `Head1`, but the lower neck must transition through `Neck1` and upper spine. Confirm both meshes use the same armature modifier and that no stale vertex groups remain.

## Hands or fingers are distorted

Check left/right bone naming, finger hierarchy, maximum influences, normalized sums, and whether LOD rules collapse bones too early. Do not enable aggressive bone collapse on unresolved hand deformation. For first-person grip distortion, read [first-person-hands.md](first-person-hands.md): compare actual native c_arms rest matrices and local axes, palm continuity, finger thickness and procedural helper data, not only bone names.

Also inspect joint-centered fitting against the canonical wrist/finger chains. Read [deformation-repair.md](deformation-repair.md) for fitting and component separation; changing bone names or adding a weighted bone-position offset is not sufficient.

## Veil or waist accessories follow the arms; skirt clips on kicks/jumps

Read [deformation-repair.md](deformation-repair.md). Inspect component-specific weights in the original pre-fit geometry, not only shared material slots or current height. A shared atlas can contain sleeves, waist ornaments and garters. Separate attachment regions before transfer and keep the canonical rig unchanged. Raised legs, tucked jumps and crouch/run are user self-check suggestions or explicitly delegated diagnostic poses. Zero offline collision counts are bounded evidence, not a guarantee for every in-game animation.

## Hair is white although images exist in tex

Inspect the hair material's actual image node, resolved image path, loaded pixel data, UV map and connection to color. Check whether an untextured overlay hides it. Then inspect SMD material identifiers and Source VMT/VTF paths. Do not recolor the whole head to compensate for a disconnected image or blindly assign every image in tex. Preserve original pixel data rather than exporting through render color management.

## Body or one region is invisible

Inspect exported SMD material lines and bodyparts, then verify the compiled MDL material table. Confirm VMT names match material identifiers and `$cdmaterials`. If geometry is absent even with wireframe/debug material, inspect export collection filters and bodygroup/QC rules.

## Pink/black textures or repeated atlas regions

Resolve every VMT `$basetexture` to `materials/<path>.vtf`. Repetition usually means UVs were collapsed, an atlas was assigned without repacking UVs, or the wrong UV map was active at export. Fix UV/material assignment in Blender; do not duplicate the same texture across unrelated material paths as a workaround.

## Correct model compiles but does not appear in the selector

Verify:

1. the addon is directly under `garrysmod/addons/<addon>`;
2. `lua/autorun/*.lua` loads without errors;
3. `modelPath` exactly matches the packaged `.mdl` path and casing;
4. both `list.Set("PlayerOptionsModel", ...)` and `player_manager.AddValidModel(...)` run;
5. there is no duplicate stale addon registering the same name/path;
6. the user has fully restarted GMod after binary/path changes.

If the user reports `util.IsValidModel(path)` is false, fix the model family/package first. If it is true but the selector entry is absent, fix Lua registration. Do not open or restart the game to obtain this evidence unless explicitly delegated.

## First-person hands do not change, or a hands package check asks for PHY

Check the exact packaged hands path, the shared display-name key in `AddValidModel` and `AddValidHands`, skin/bodygroup settings, and whether the selected SWEP uses GMod hands. A weapon with baked-in arms or without hands support may retain its own arms; do not globally override other weapons to compensate. The user restarts and reselects the character.

If a static check is actually requested or needed for a package error, run the addon helper with `-ModelKind Hands`; its default is `PlayerModel`. Hands require MDL/VVD/DX90/DX80 VTX and matching checksums, not player-model PHY, selector registration or `m_anm.mdl`. See [first-person-hands.md](first-person-hands.md) for the separate pipeline.

## Model disappears after a new install

Compare the staged and installed addon recursively by relative path, size, and SHA-256. Restore the dated backup if files differ or the new build fails. Never delete the last working addon while debugging.

## Compile succeeds with warnings

Treat missing bones, missing materials, bad weight links, degenerate physics, and bounding-box warnings as actionable. StudioMDL producing files is not evidence that a player model is usable.

## Bone comparison fails after an unchanged import/export

Euler triples can differ by a full turn or an alternative Euler decomposition while describing the same orientation. Use the current validator's angular comparison and inspect its separate translation/angular errors. The measured SMD round-trip needed up to about `0.00018` radians of tolerance; the default is `0.0002`. Do not widen tolerances to hide actual rest-pose changes or substitute the reference node table into the candidate.

## Blender weights pass but the SMD contains zero-weight links

The exporter may round a tiny positive link to zero while still counting it. Clean tiny/zero weights, limit influences, normalize, re-export to a new output and validate the written file. Inspect unweighted vertices afterward. A clean operator return alone is insufficient.

## Source tool fails under a Unicode path

If an old Source executable reports file-handle/path errors, retry the same inputs in a unique, short ASCII temporary directory. Copy the outputs back and compare file counts/hashes. Keep the original workspace and source paths intact; do not globally change the user's locale or rename the project. Record both the command and its actual output path.

## Export writes files, then cached Blender objects raise StructRNA errors

Some Source Tools bake/undo operations invalidate cached Python object references. Reacquire armatures and meshes by name from the current scene before inspecting them. Check output timestamps, complete SMD blocks, the written-file validator and the restored scene state before deciding whether export failed. A late wrapper exception does not by itself invalidate a fully written export; incomplete or invalid files still require repair. Do not blindly export again or suppress every exception.

## HLMV loads statistics but the viewport is blank

This branch applies only if the user has explicitly requested HLMV inspection. Record file loading separately from visual acceptance. Check model bounds, camera/framing, active sequence/bodygroup, game search paths and rendering compatibility within that request. If HLMV remains unavailable, report the limitation and leave game verification to the user; do not automatically switch to a game test or claim that empty screenshots prove a correct model. HLMV is not a default completion gate.

## Verifying changes to this skill

After editing a script, run its relevant isolated regression with an available runtime. `scripts/test_validate_smd.py` covers equivalent Euler forms versus real rotation changes, remapped IDs, malformed skeletons, invalid weights, height and CLI reports. Use an existing failing export as a fixture only when available and relevant; do not edit Blender or game files to create one. Re-run skill-creator's `quick_validate.py` after instruction changes; it checks skill packaging, not GMod behavior.

Run `scripts/test_toolchain_helpers.ps1` for isolated discovery and mocked-download tests, and `scripts/test_validate_gmod_addon.ps1` for player/hands package fixtures when those scripts change. These tests must not download/install programs, edit Blender scenes or write into the active game addon. At execution time, browse current official download links only after confirming a missing required tool; wait for the installation choice before downloading or configuring anything. Actual production operations provide their own error evidence, not a mandatory acceptance suite.
