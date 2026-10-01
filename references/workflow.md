# Classic-reference conversion workflow

## 1. Choose the reference model

Use a model already installed with GMod/HL2 and close to the supplied character's body type. Typical starting points:

- neutral adult male: `models/player/group01/male_07.mdl` or a nearby male citizen;
- white lab coat: `models/player/kleiner.mdl`;
- neutral adult female: an installed female citizen or Alyx-derived player example, paired with the female GMod animation include.

Inspect the actual local model before selecting it. A matching silhouette reduces weight-transfer work, but the decisive requirements are a standard ValveBiped hierarchy and the correct GMod player animation family.

Create a reference folder containing the copied/extracted MDL family and a separate Crowbar decompile output. Record the source model path and hashes. Never decompile over a prior reference.

## 2. Mine the decompiled output

Retain and inspect:

- QC/QCI structure and `$modelname`, `$cdmaterials`, `$attachment`, `$include`, `$includemodel`, `$collisionjoints`, and LOD directives;
- reference SMD `nodes` and frame-0 `skeleton` blocks;
- physics SMD and hitbox/ragdoll conventions;
- male/female animation include choice;
- material names only as mapping examples.

The canonical compatibility contract is bone name + parent relationship + bind/rest transform + vertex weight target. Numeric IDs are file-local and must be remapped consistently if they change. Replacing a node table without transforming the mesh and all weighted IDs into that bind space produces the familiar exploded/giant model.

## 3. Blender scene construction

1. Save a work copy and record dimensions, source geometry, UVs and materials. Do not render baseline views by default.
2. Import the classic reference first so it establishes the canonical armature and coordinate convention.
3. Import/link the custom model. Keep its original materials and UVs until a verified backup exists.
4. Match mesh dimensions and landmarks to the classic skeleton: soles, ankles, knees, pelvis, shoulders, elbows, wrists, neck base, jaw, and head crown.
5. Apply mesh rotation/scale before final weighting. Keep the armature transform and rest pose unchanged.
6. Remove or disable the classic visible mesh after it has served as a transfer/reference surface.
7. Transfer weights by proximity/topology where sensible, then manually correct joints. Normalize and remove zero/invalid groups.
8. For a separate head, preserve the head UV and material. Blend only the neck seam; do not smear a head atlas onto the neck unless explicitly requested.
9. Inspect affected joint placement and weight assignments as part of production. Follow [first-person-hands.md](first-person-hands.md) when producing a separate c_hands mesh.
10. Save a clean rest-pose checkpoint. Visual and animation acceptance belongs to the user unless they explicitly delegate it.

Do not use “move each vertex by each bone's positional delta” as a rig-fitting method. It double-applies transforms and distorts shoulders, limbs, and neck.

Preserve the original silhouette and anatomical proportions when fitting. If compatibility requires a substantial design/proportion change, explain the concrete difference and seek the user's choice of a closer reference, a limited accepted fit, or custom rig/animation retargeting. Reuse an existing choice. A custom-rig route requires a complete compatible animation library; never alter the canonical rest pose and silently reuse its original animation includes. Do not add a mandatory render or acceptance gate. If a preview is needed to decide a proposed appearance change, ask for that limited preview scope.

### Weight transfer and optional pose diagnosis

- Match shoulders, elbows, wrists, hips, knees and ankles before transferring weights. A matching total height alone does not establish a fit.
- For Data Transfer by vertex-group name, create the corresponding destination groups when absent. Applying the modifier can appear successful while transferring no weights. Check the resulting per-vertex assignments, not only the operator status.
- In Object Mode with the intended mesh both active and selected, clean zero/tiny weights (a starting threshold of `1e-5` worked for the observed six-decimal SMD exporter), limit to three influences, then normalize. Preserve a sole valid weight. Confirm zero unweighted vertices and inspect the exported numbers; do not raise the threshold without checking deformation.
- Nearest-surface transfer can bind long hair or skirt pieces to nearby limbs. Inspect those regions separately. A texture atlas can contain hair, skin and clothing at once; atlas filename alone is not evidence that all its faces should follow the head.
- Only when the user explicitly requests a pose preview or delegates diagnosis, save copies of affected `matrix_basis` values, rotation modes and animation state. Restore by assignment in `finally` and update the dependency graph. Do not save a diagnostic pose into the export checkpoint.
- For an explicitly requested render, check that its camera frames the evaluated mesh, then inspect the returned image. A requested filename or tool transport success is not evidence that rendering succeeded. Do not render or perform pose stress tests by default.

Blender MCP code must return a JSON-serializable dictionary in `result`; an operator's return value is a set, so store it separately or convert it to a list. A wrapper serialization error may occur after the operator changed the scene. Inspect the live state before repeating a mutation.

## 4. Materials and textures

Each independent GMod-adjustable region needs an independent Source material name on exported triangles. A practical set is:

- `character_head`
- `character_neck`
- `character_hands`
- `character_upper`
- `character_lower`
- `character_shoes`

Material slots alone are insufficient if export collapses all triangles to one material. Inspect the SMD material lines after export.

Keep editable PNG/TGA sources in the work tree. Convert final textures to VTF and create matching VMT files, for example:

```text
"VertexLitGeneric"
{
    "$basetexture" "models/player/character/character_head"
    "$model" "1"
}
```

Preserve original image bytes when copying or unpacking textures. `Image.save_render()` applies render color-management settings and is not a byte-preserving texture export. If re-encoding is necessary, verify color space, alpha and representative pixel values against the source. An alpha channel's presence does not by itself justify `$translucent`; inspect the intended material and UV region before choosing opaque, alpha-test or blended behavior. Shared atlas textures are fine while Source material identifiers remain independent.

Before dropping a missing-image overlay, establish that it is decorative/redundant geometry and preserve a checkpoint. Do not delete all faces with missing textures or all transparent materials.

## 5. SMD/QC and compile

Export at a scale that yields approximately human Source dimensions. Handle invalid skeletons, weights and incomplete exports as production errors. `validate_smd.py` is an optional structural helper for an explicitly requested static check or an actual export/compile problem:

```powershell
& $python scripts/validate_smd.py --candidate character_reference.smd --reference classic_reference.smd --summary --report smd-validation.json
```

The validator checks Source Z height (default 50–100 units), finite positive normalized weights, and at most three influences per vertex, matching Valve's [`MAX_NUM_BONES_PER_VERT`](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/studio.h). For an intentionally unusual player scale, pass explicit `--min-height` and `--max-height` values derived from the chosen reference. First-person arms use their own reference bounds, not the human-height default. The user checks in-game scale.

Set `$python` to the `Python` path returned by the detector, including Blender's bundled runtime when needed. Do not assume `python` is on PATH. Exit code 0 means the requested structural check passed; 2 means validation or input failure. `--report` stores complete bone tables while `--summary` keeps console output short. A pass is not game acceptance and is not a default handoff requirement.

The script targets a reference mesh, not an animation-only SMD. It rejects duplicate/missing/cyclic skeleton data, incomplete frame 0, non-finite geometry/UV/transform/weight values and malformed triangles. It compares rotations as orientations, not raw Euler components. Default position tolerance is `0.0002` Source units and angular tolerance is `0.0002` radians, accommodating measured import/export rounding; use `--position-tolerance` and `--rotation-tolerance` only with a diagnosed reason. Extra custom bones are reported rather than automatically rejected; verify their valid parenting and intended animation behavior. The explicit-weight policy requires normalized positive links; omitted or zero-link lists are supported as rigid binding to the primary bone.

Build the QC from the selected GMod example. Official GMod player models normally need the appropriate `commonbones.qci`, `ragdoll.qci`, `hitbox.qci`, `standardikchains.qci`, LOD rules, and `m_anm.mdl` or `f_anm.mdl`. The authoritative checklist is the Facepunch player-model compilation page.

Compile into an isolated game/staging directory, then collect the entire output family. `.ani` is optional and usually absent; `.mdl`, `.vvd`, `.dx90.vtx`, and `.phy` are expected for this workflow.

## 6. Addon registration

Use a unique model path such as `models/player/my_slug/my_slug.mdl`. Register exactly that path:

```lua
if SERVER then AddCSLuaFile() end

local modelName = "Display Name"
local modelPath = "models/player/my_slug/my_slug.mdl"

list.Set("PlayerOptionsModel", modelName, modelPath)
player_manager.AddValidModel(modelName, modelPath)
```

For separate first-person hands, add the `AddValidHands` registration described in [first-person-hands.md](first-person-hands.md). Compile and package that model independently of the player model.

Install the completed staging folder after production has produced the required model family, materials and exact registration paths. Retain the previous installed addon as a dated backup. The addon validator is an optional static helper for a user-requested check or a real packaging failure; use `-ModelKind PlayerModel` (the default) for the player and `-ModelKind Hands` for c_hands.

Keep that backup outside `garrysmod/addons` so a stale registration/model path cannot also be mounted. Confirm the copy completed by relative paths, sizes and hashes. Do not launch or restart GMod to finish installation.

The addon helper is a static package check, not a Lua interpreter or compiled material-table reader. It recognizes direct model-path literals and the illustrated `modelPath` variable (`handsPath` for hands); inspect custom registration code directly and leave runtime behavior to the user. Ensure exported SMD material identifiers agree with the compiled model's material table and `$cdmaterials` search paths as part of packaging. Having one valid VMT somewhere in the addon does not prove every model material resolves.

The optional VTF checks reject directories, empty files, bad desktop VTF 7.x magic/version, invalid header extents and zero dimensions using the [Valve header layout](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/vtf/vtf.h). This is basic sanity, not full texture decoding or visual acceptance. If an actual conversion error requires reopening a texture, diagnose that error only; do not append a visual-test suite.

## 7. User acceptance after handoff

Default handoff follows successful production, compilation, packaging and reversible installation. Give the user the addon/model paths, work file, relevant logs and backup location, and state that the game effect is for them to verify. Do not require screenshots, HLMV evidence, offline pose renders or a GMod test before delivery. Do not open, close, restart or operate those applications for acceptance unless the user explicitly delegates a specific check.

Offer a short self-check list. The user fully restarts GMod, selects the character again, and checks:

- selector entry after a full restart;
- human scale and intact bind pose;
- stable idle/walk/run/crouch/jump and weapon poses;
- acceptable neck, shoulder, wrist, pelvis, knee, and ankle deformation;
- no missing/pink/checkerboard materials;
- correct front/side/back head texture;
- independent head material and all other requested material regions;
- ragdoll without exploding or collapsing.
- first-person hands with supported weapons, including grip, fire and reload.

HLMV is optional for the user's inspection. Keep the last known-good stage for rollback. Do not claim runtime or visual acceptance from compile success. If the user requests diagnosis later, limit it to the reported issue and restore any temporary scene changes.
