from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path


def block(lines: list[str], name: str, optional: bool = False) -> list[str]:
    starts = [i for i, line in enumerate(lines) if line.strip() == name]
    if not starts and optional:
        return []
    if len(starts) != 1:
        raise ValueError(f"Expected exactly one {name} block")
    start = starts[0]
    for end in range(start + 1, len(lines)):
        if lines[end].strip() == "end":
            return lines[start + 1:end]
    raise ValueError(f"Unterminated {name} block")


def parse_smd(path: Path) -> dict:
    lines = [line.split("//", 1)[0].strip() for line in path.read_text(encoding="utf-8-sig").splitlines()]
    lines = [line for line in lines if line]
    if not lines or lines[0] != "version 1":
        raise ValueError("Expected SMD version 1")
    nodes_by_id: dict[int, tuple[str, int]] = {}
    names = set()
    for line in block(lines, "nodes"):
        match = re.fullmatch(r'(\d+)\s+"([^"\r\n]+)"\s+(-?\d+)', line)
        if not match:
            raise ValueError(f"Malformed node: {line}")
        bone_id, name, parent = int(match[1]), match[2], int(match[3])
        if bone_id in nodes_by_id or name in names:
            raise ValueError(f"Duplicate bone ID or name: {line}")
        nodes_by_id[bone_id] = (name, parent)
        names.add(name)
    if not nodes_by_id:
        raise ValueError("Empty skeleton")
    for bone_id, (name, _) in nodes_by_id.items():
        seen = set()
        current = bone_id
        while current != -1:
            if current in seen:
                raise ValueError(f"Cyclic bone hierarchy at {name}")
            if current not in nodes_by_id:
                raise ValueError(f"Missing parent {current} in hierarchy of {name}")
            seen.add(current)
            current = nodes_by_id[current][1]

    frame_zero: dict[int, list[float]] = {}
    in_zero = False
    frame = None
    frame_ids = set()
    seen_in_frame = set()
    for line in block(lines, "skeleton"):
        stripped = line.split("#", 1)[0].strip()
        if stripped.startswith("time "):
            fields = stripped.split()
            if len(fields) != 2:
                raise ValueError(f"Malformed frame: {line}")
            frame = int(fields[1])
            if frame in frame_ids:
                raise ValueError(f"Duplicate frame {frame}")
            frame_ids.add(frame)
            seen_in_frame = set()
            in_zero = frame == 0
            continue
        if stripped:
            fields = stripped.split()
            if frame is None or len(fields) != 7:
                raise ValueError(f"Malformed skeleton transform: {line}")
            bone_id = int(fields[0])
            values = [float(x) for x in fields[1:]]
            if bone_id not in nodes_by_id or bone_id in seen_in_frame:
                raise ValueError(f"Unknown or duplicate bone {bone_id} in frame {frame}")
            if not all(math.isfinite(x) for x in values):
                raise ValueError(f"Non-finite transform for bone {bone_id}")
            seen_in_frame.add(bone_id)
            if in_zero:
                frame_zero[bone_id] = values
    missing = sorted(set(nodes_by_id) - set(frame_zero))
    if missing:
        raise ValueError(f"Missing frame-0 transforms for bone IDs {missing}")

    materials: dict[str, int] = {}
    coords: list[list[float]] = []
    invalid_weight_ids: set[int] = set()
    bad_weight_sums: list[float] = []
    bad_weight_values: list[float] = []
    too_many_influences = 0
    max_influences = 0
    duplicate_weight_links = 0
    triangles = block(lines, "triangles", optional=True)
    if len(triangles) % 4:
        raise ValueError("Incomplete triangle: expected a material and three vertices")

    index = 0
    while index < len(triangles):
        material = triangles[index].strip()
        if not material:
            index += 1
            continue
        materials[material] = materials.get(material, 0) + 1
        index += 1
        for _ in range(3):
            fields = triangles[index].split()
            if len(fields) < 9:
                raise ValueError(f"Incomplete vertex: {triangles[index]}")
            primary = int(fields[0])
            if primary not in nodes_by_id:
                invalid_weight_ids.add(primary)
            values = [float(x) for x in fields[1:9]]
            if not all(math.isfinite(x) for x in values):
                raise ValueError("Non-finite vertex position, normal or UV")
            coords.append(values[:3])
            if len(fields) > 9:
                count = int(fields[9])
                if count < 0 or len(fields) != 10 + count * 2:
                    raise ValueError(f"Malformed SMD vertex weight links in {path}: {triangles[index]}")
                # SMD allows explicit zero links: the vertex is rigidly bound to primary.
                if count == 0:
                    max_influences = max(max_influences, 1)
                    index += 1
                    continue
                max_influences = max(max_influences, count)
                if count > 3:
                    too_many_influences += 1
                weights = []
                linked_ids = []
                for link in range(count):
                    bone_id = int(fields[10 + link * 2])
                    weight = float(fields[11 + link * 2])
                    weights.append(weight)
                    linked_ids.append(bone_id)
                    if not math.isfinite(weight):
                        raise ValueError("Non-finite vertex weight")
                    if weight <= 0 or weight > 1:
                        bad_weight_values.append(weight)
                    if bone_id not in nodes_by_id:
                        invalid_weight_ids.add(bone_id)
                duplicate_weight_links += len(set(linked_ids)) != len(linked_ids)
                total = sum(weights)
                if not math.isfinite(total):
                    raise ValueError("Vertex weight sum overflow")
                if not math.isclose(total, 1.0, rel_tol=1e-4, abs_tol=1e-4):
                    bad_weight_sums.append(total)
            else:
                max_influences = max(max_influences, 1)
            index += 1

    by_name = {name: bone_id for bone_id, (name, _) in nodes_by_id.items()}
    parents = {}
    for bone_id, (name, parent_id) in nodes_by_id.items():
        parents[name] = None if parent_id == -1 else nodes_by_id.get(parent_id, (f"<missing:{parent_id}>", -1))[0]
    transforms = {nodes_by_id[bone_id][0]: values for bone_id, values in frame_zero.items() if bone_id in nodes_by_id}

    bounds_min = [min(p[i] for p in coords) for i in range(3)] if coords else None
    bounds_max = [max(p[i] for p in coords) for i in range(3)] if coords else None
    dimensions = [bounds_max[i] - bounds_min[i] for i in range(3)] if coords else None
    if dimensions and not all(math.isfinite(x) for x in dimensions):
        raise ValueError("Geometry bounds overflow")
    return {
        "file": str(path),
        "node_count": len(nodes_by_id),
        "nodes": sorted(by_name),
        "parents": parents,
        "transforms": transforms,
        "materials": materials,
        "triangle_count": sum(materials.values()),
        "bounds_min": bounds_min,
        "bounds_max": bounds_max,
        "dimensions": dimensions,
        "largest_dimension": max(dimensions) if dimensions else None,
        "height": dimensions[2] if dimensions else None,
        "invalid_weight_ids": sorted(invalid_weight_ids),
        "bad_weight_sum_count": len(bad_weight_sums),
        "bad_weight_sum_range": [min(bad_weight_sums), max(bad_weight_sums)] if bad_weight_sums else None,
        "bad_weight_value_count": len(bad_weight_values),
        "too_many_influences": too_many_influences,
        "max_influences": max_influences,
        "duplicate_weight_link_count": duplicate_weight_links,
    }


def compare(candidate: dict, reference: dict, tolerance: float, rotation_tolerance: float | None = None) -> dict:
    rotation_tolerance = tolerance if rotation_tolerance is None else rotation_tolerance
    candidate_nodes = set(candidate["nodes"])
    reference_nodes = set(reference["nodes"])
    common = candidate_nodes & reference_nodes
    parent_mismatches = {
        name: [candidate["parents"].get(name), reference["parents"].get(name)]
        for name in sorted(common)
        if candidate["parents"].get(name) != reference["parents"].get(name)
    }
    transform_mismatches = {}
    for name in sorted(common):
        candidate_transform = candidate["transforms"].get(name)
        reference_transform = reference["transforms"].get(name)
        if candidate_transform is None or reference_transform is None:
            transform_mismatches[name] = [candidate_transform, reference_transform]
            continue
        position_delta = max(abs(x - y) for x, y in zip(candidate_transform[:3], reference_transform[:3]))
        if not math.isfinite(position_delta):
            raise ValueError(f"Transform difference overflow for {name}")
        distance = math.sqrt(sum(
            (x - y) ** 2
            for x, y in zip(
                euler_xyz_matrix(candidate_transform[3:]),
                euler_xyz_matrix(reference_transform[3:]),
            )
        ))
        rotation_delta = 2 * math.asin(min(1.0, distance / (2 * math.sqrt(2))))
        if position_delta > tolerance or rotation_delta > rotation_tolerance:
            transform_mismatches[name] = {"position_source_units": position_delta, "rotation_radians": rotation_delta}
    return {
        "missing_reference_bones": sorted(reference_nodes - candidate_nodes),
        "extra_candidate_bones": sorted(candidate_nodes - reference_nodes),
        "parent_mismatches": parent_mismatches,
        "rest_transform_mismatches": transform_mismatches,
    }


def euler_xyz_matrix(angles: list[float]) -> tuple[float, ...]:
    """Compare orientation, not Euler spelling (which is non-unique)."""
    x, y, z = angles
    cx, cy, cz = math.cos(x), math.cos(y), math.cos(z)
    sx, sy, sz = math.sin(x), math.sin(y), math.sin(z)
    return (
        cy * cz, cz * sx * sy - cx * sz, sx * sz + cx * cz * sy,
        cy * sz, cx * cz + sx * sy * sz, cx * sy * sz - cz * sx,
        -sy, cy * sx, cx * cy,
    )


def validate(candidate: dict, reference: dict | None = None, *, min_height: float = 50,
             max_height: float = 100, position_tolerance: float = 2e-4,
             rotation_tolerance: float = 2e-4) -> dict:
    report = {"candidate": candidate}
    failures = []
    if candidate["invalid_weight_ids"]:
        failures.append("invalid_weight_ids")
    if candidate["bad_weight_sum_count"]:
        failures.append("non_normalized_weights")
    if candidate["bad_weight_value_count"]:
        failures.append("invalid_weight_values")
    if candidate["too_many_influences"]:
        failures.append("too_many_bone_influences")
    if candidate["duplicate_weight_link_count"]:
        failures.append("duplicate_weight_links")
    if candidate["height"] is None or not min_height <= candidate["height"] <= max_height:
        failures.append("implausible_source_height")

    if reference is not None:
        compatibility = compare(candidate, reference, position_tolerance, rotation_tolerance)
        report["reference"] = reference
        report["compatibility"] = compatibility
        if compatibility["missing_reference_bones"]:
            failures.append("missing_reference_bones")
        if compatibility["parent_mismatches"]:
            failures.append("parent_mismatches")
        if compatibility["rest_transform_mismatches"]:
            failures.append("rest_transform_mismatches")

    report["valid"] = not failures
    report["failures"] = failures
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a reference-mesh SMD: structure, weights, Source Z height, and canonical bind pose.")
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--reference", type=Path)
    parser.add_argument("--tolerance", type=float, help="Compatibility alias: override both position and rotation tolerance")
    parser.add_argument("--position-tolerance", type=float, default=2e-4, help="Source units; allows measured import/export rounding")
    parser.add_argument("--rotation-tolerance", type=float, default=2e-4, help="Angular difference in radians")
    parser.add_argument("--min-height", type=float, default=50.0)
    parser.add_argument("--max-height", type=float, default=100.0)
    parser.add_argument("--report", type=Path, help="Write the full JSON report to this path")
    parser.add_argument("--summary", action="store_true", help="Print a compact report without bone tables")
    args = parser.parse_args()
    if args.tolerance is not None:
        args.position_tolerance = args.rotation_tolerance = args.tolerance
    limits = (args.position_tolerance, args.rotation_tolerance, args.min_height, args.max_height)
    if not all(math.isfinite(x) and x >= 0 for x in limits) or args.min_height > args.max_height:
        parser.error("Tolerances and height bounds must be finite, nonnegative, and ordered")
    try:
        candidate = parse_smd(args.candidate)
        reference = parse_smd(args.reference) if args.reference else None
        report = validate(candidate, reference, min_height=args.min_height, max_height=args.max_height,
                          position_tolerance=args.position_tolerance, rotation_tolerance=args.rotation_tolerance)
    except (OSError, UnicodeError, ValueError, OverflowError) as exc:
        report = {"valid": False, "failures": ["malformed_or_unreadable_smd"], "error": str(exc)}
    payload = json.dumps(report, ensure_ascii=True, indent=2, allow_nan=False)
    if args.report:
        try:
            args.report.write_text(payload + "\n", encoding="utf-8")
        except OSError as exc:
            parser.exit(2, f"Cannot write report: {exc}\n")
    if args.summary and "candidate" in report:
        output = {key: report[key] for key in ("valid", "failures")}
        output.update({key: report["candidate"][key] for key in ("node_count", "triangle_count", "height", "max_influences")})
        if "compatibility" in report:
            output["compatibility"] = report["compatibility"]
        print(json.dumps(output, ensure_ascii=True, indent=2))
    else:
        print(payload)
    return 0 if report["valid"] else 2


if __name__ == "__main__":
    raise SystemExit(main())
