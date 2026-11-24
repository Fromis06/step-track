"""Generate an offline sculpted multi-part 3D human body Wavefront OBJ & MTL asset."""
from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = REPO_ROOT / "StepTrack/Resources/Models3D/human_body.obj"
MAX_OBJ_BYTES = 1024 * 1024

SELECTABLE_REGIONS: tuple[str, ...] = (
    "chest",
    "back_upper",
    "back_lats",
    "back_lower",
    "shoulders",
    "biceps",
    "triceps",
    "forearms",
    "abs",
    "glutes",
    "quads",
    "hamstrings",
    "calves",
    "neck",
    "cardio",
)
STRUCTURAL_REGIONS: tuple[str, ...] = (
    "head",
    "torso_core",
    "hands",
    "feet",
)
ALL_REGIONS: tuple[str, ...] = SELECTABLE_REGIONS + STRUCTURAL_REGIONS


def _cross(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def _sub(a: tuple[float, float, float], b: tuple[float, float, float]) -> tuple[float, float, float]:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _dot(a: tuple[float, float, float], b: tuple[float, float, float]) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _normalize(v: tuple[float, float, float]) -> tuple[float, float, float]:
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
    if length < 1e-12:
        return (0.0, 1.0, 0.0)
    return (v[0] / length, v[1] / length, v[2] / length)


def _signed_volume(verts: list[tuple[float, float, float]], tris: list[tuple[int, int, int]]) -> float:
    vol = 0.0
    for i0, i1, i2 in tris:
        vol += _dot(verts[i0], _cross(verts[i1], verts[i2])) / 6.0
    return vol


def _ensure_outward_winding(verts: list[tuple[float, float, float]], tris: list[tuple[int, int, int]]) -> list[tuple[int, int, int]]:
    if _signed_volume(verts, tris) < 0.0:
        return [(i0, i2, i1) for (i0, i1, i2) in tris]
    return tris


def _build_lofted_part(
    rings: list[tuple[float, float, float, float, float]],
    segs: int = 16,
    tilt_z: float = 0.0,
) -> tuple[list[tuple[float, float, float]], list[tuple[int, int, int]]]:
    """Build a watertight closed mesh from rings: (cx, cy, cz, rx, rz)."""
    verts: list[tuple[float, float, float]] = []
    tris: list[tuple[int, int, int]] = []

    cos_t = math.cos(tilt_z)
    sin_t = math.sin(tilt_z)

    def _rot(dx: float, dy: float, dz: float, cx: float, cy: float, cz: float) -> tuple[float, float, float]:
        rx = dx * cos_t - dy * sin_t
        ry = dx * sin_t + dy * cos_t
        return (cx + rx, cy + ry, cz + dz)

    # Bottom pole
    bx, by, bz, brx, brz = rings[0]
    bot_idx = len(verts)
    verts.append(_rot(0.0, -0.008, 0.0, bx, by, bz))

    ring_starts: list[int] = []
    for cx, cy, cz, rx, rz in rings:
        ring_starts.append(len(verts))
        for i in range(segs):
            theta = (2.0 * math.pi * i) / segs
            dx = rx * math.cos(theta)
            dz = -rz * math.sin(theta)
            verts.append(_rot(dx, 0.0, dz, cx, cy, cz))

    # Top pole
    tx, ty, tz, _, _ = rings[-1]
    top_idx = len(verts)
    verts.append(_rot(0.0, 0.008, 0.0, tx, ty, tz))

    # Bottom cap
    r0 = ring_starts[0]
    for i in range(segs):
        ni = (i + 1) % segs
        tris.append((bot_idx, r0 + ni, r0 + i))

    # Side quads
    for r in range(len(rings) - 1):
        a0 = ring_starts[r]
        b0 = ring_starts[r + 1]
        for i in range(segs):
            ni = (i + 1) % segs
            tris.append((a0 + i, a0 + ni, b0 + ni))
            tris.append((a0 + i, b0 + ni, b0 + i))

    # Top cap
    rn = ring_starts[-1]
    for i in range(segs):
        ni = (i + 1) % segs
        tris.append((top_idx, rn + i, rn + ni))

    tris = _ensure_outward_winding(verts, tris)
    return verts, tris


def _build_ellipsoid(
    cx: float,
    cy: float,
    cz: float,
    rx: float,
    ry: float,
    rz: float,
    lat_rings: int = 8,
    segs: int = 16,
    tilt_z: float = 0.0,
) -> tuple[list[tuple[float, float, float]], list[tuple[int, int, int]]]:
    rings: list[tuple[float, float, float, float, float]] = []
    for j in range(1, lat_rings):
        phi = -0.5 * math.pi + (math.pi * j) / lat_rings
        c_phi = math.cos(phi)
        s_phi = math.sin(phi)
        rings.append((cx, cy + ry * s_phi, cz, max(0.006, rx * c_phi), max(0.006, rz * c_phi)))
    return _build_lofted_part(rings, segs=segs, tilt_z=tilt_z)


def _build_heart_emblem(cx: float, cy: float, cz: float, scale: float = 0.024) -> tuple[list[tuple[float, float, float]], list[tuple[int, int, int]]]:
    """Sculpted 3D heart emblem facing +Z on upper-left chest."""
    segs = 20
    verts: list[tuple[float, float, float]] = []
    tris: list[tuple[int, int, int]] = []

    profile: list[tuple[float, float]] = []
    for i in range(segs):
        t = (2.0 * math.pi * i) / segs
        hx = 16.0 * (math.sin(t) ** 3)
        hy = 13.0 * math.cos(t) - 5.0 * math.cos(2 * t) - 2.0 * math.cos(3 * t) - math.cos(4 * t)
        profile.append((hx * scale / 16.0, hy * scale / 16.0))

    back_center = 0
    verts.append((cx, cy, cz - 0.010))
    front_center = 1
    verts.append((cx, cy, cz + 0.022))

    back_ring = len(verts)
    for px, py in profile:
        verts.append((cx + px * 0.92, cy + py * 0.92, cz - 0.006))

    front_ring = len(verts)
    for px, py in profile:
        verts.append((cx + px, cy + py, cz + 0.018))

    for i in range(segs):
        ni = (i + 1) % segs
        tris.append((back_center, back_ring + ni, back_ring + i))
        tris.append((front_center, front_ring + i, front_ring + ni))
        tris.append((back_ring + i, back_ring + ni, front_ring + ni))
        tris.append((back_ring + i, front_ring + ni, front_ring + i))

    tris = _ensure_outward_winding(verts, tris)
    return verts, tris


def _mirror_parts(parts: list[tuple[list[tuple[float, float, float]], list[tuple[int, int, int]]]]) -> tuple[list[tuple[float, float, float]], list[tuple[int, int, int]]]:
    all_verts: list[tuple[float, float, float]] = []
    all_tris: list[tuple[int, int, int]] = []
    for verts, tris in parts:
        offset = len(all_verts)
        all_verts.extend(verts)
        all_tris.extend((a + offset, b + offset, c + offset) for a, b, c in tris)
    return all_verts, all_tris


def _build_body_parts() -> dict[str, tuple[str, list[tuple[float, float, float]], list[tuple[int, int, int]]]]:
    parts: dict[str, tuple[str, list[tuple[float, float, float]], list[tuple[int, int, int]]]] = {}

    # Structural: head
    parts["head"] = (
        "body_structural",
        *_build_lofted_part(
            [
                (0.0, 1.62, 0.005, 0.056, 0.062),
                (0.0, 1.67, 0.012, 0.072, 0.084),
                (0.0, 1.73, 0.008, 0.082, 0.095),
                (0.0, 1.79, 0.002, 0.076, 0.088),
                (0.0, 1.83, -0.002, 0.048, 0.055),
            ],
            segs=16,
        ),
    )

    # Structural: recessed torso_core so selectable muscle shells sit proud outside it
    parts["torso_core"] = (
        "body_structural",
        *_build_lofted_part(
            [
                (0.0, 0.84, -0.005, 0.120, 0.082),
                (0.0, 0.94, -0.002, 0.114, 0.080),
                (0.0, 1.08, 0.002, 0.118, 0.084),
                (0.0, 1.24, 0.004, 0.140, 0.092),
                (0.0, 1.40, 0.002, 0.152, 0.092),
                (0.0, 1.49, 0.000, 0.112, 0.074),
            ],
            segs=18,
        ),
    )

    # Structural: hands
    hand_l = _build_ellipsoid(0.325, 0.80, 0.012, 0.032, 0.068, 0.022, lat_rings=6, segs=12, tilt_z=0.10)
    hand_r = _build_ellipsoid(-0.325, 0.80, 0.012, 0.032, 0.068, 0.022, lat_rings=6, segs=12, tilt_z=-0.10)
    parts["hands"] = ("body_structural", *_mirror_parts([hand_l, hand_r]))

    # Structural: feet
    foot_l = _build_lofted_part(
        [
            (0.105, 0.01, 0.035, 0.046, 0.108),
            (0.105, 0.05, 0.025, 0.044, 0.095),
            (0.102, 0.10, -0.005, 0.038, 0.052),
        ],
        segs=12,
    )
    foot_r = _build_lofted_part(
        [
            (-0.105, 0.01, 0.035, 0.046, 0.108),
            (-0.105, 0.05, 0.025, 0.044, 0.095),
            (-0.102, 0.10, -0.005, 0.038, 0.052),
        ],
        segs=12,
    )
    parts["feet"] = ("body_structural", *_mirror_parts([foot_l, foot_r]))

    # Selectable: neck
    parts["neck"] = (
        "muscle_selectable",
        *_build_lofted_part(
            [
                (0.0, 1.49, 0.0, 0.064, 0.060),
                (0.0, 1.55, 0.002, 0.054, 0.054),
                (0.0, 1.61, 0.004, 0.051, 0.052),
            ],
            segs=14,
        ),
    )

    # Selectable: chest (bilateral pectorals, +Z)
    pec_l = _build_ellipsoid(0.082, 1.34, 0.088, 0.072, 0.088, 0.048, lat_rings=8, segs=14, tilt_z=0.12)
    pec_r = _build_ellipsoid(-0.082, 1.34, 0.088, 0.072, 0.088, 0.048, lat_rings=8, segs=14, tilt_z=-0.12)
    parts["chest"] = ("muscle_selectable", *_mirror_parts([pec_l, pec_r]))

    # Selectable: cardio (emblem proud on upper-left chest)
    parts["cardio"] = ("cardio_emblem", *_build_heart_emblem(0.062, 1.365, 0.142, scale=0.024))

    # Selectable: abs (rectus abdominis column, +Z)
    abs_segments = [
        _build_ellipsoid(0.0, 1.18, 0.086, 0.074, 0.046, 0.034, lat_rings=6, segs=14),
        _build_ellipsoid(0.0, 1.10, 0.084, 0.070, 0.044, 0.034, lat_rings=6, segs=14),
        _build_ellipsoid(0.0, 1.01, 0.082, 0.064, 0.052, 0.032, lat_rings=6, segs=14),
    ]
    parts["abs"] = ("muscle_selectable", *_mirror_parts(abs_segments))

    # Selectable: back_upper (traps & rhomboids, -Z)
    parts["back_upper"] = (
        "muscle_selectable",
        *_build_lofted_part(
            [
                (0.0, 1.35, -0.078, 0.085, 0.038),
                (0.0, 1.43, -0.082, 0.135, 0.044),
                (0.0, 1.50, -0.068, 0.112, 0.038),
                (0.0, 1.54, -0.048, 0.066, 0.030),
            ],
            segs=16,
        ),
    )

    # Selectable: back_lats (bilateral V-taper lats, -Z)
    lat_l = _build_ellipsoid(0.115, 1.24, -0.068, 0.064, 0.115, 0.046, lat_rings=8, segs=14, tilt_z=-0.22)
    lat_r = _build_ellipsoid(-0.115, 1.24, -0.068, 0.064, 0.115, 0.046, lat_rings=8, segs=14, tilt_z=0.22)
    parts["back_lats"] = ("muscle_selectable", *_mirror_parts([lat_l, lat_r]))

    # Selectable: back_lower (lumbar erectors, -Z)
    parts["back_lower"] = (
        "muscle_selectable",
        *_build_lofted_part(
            [
                (0.0, 0.97, -0.078, 0.068, 0.036),
                (0.0, 1.06, -0.082, 0.064, 0.038),
                (0.0, 1.15, -0.080, 0.060, 0.034),
            ],
            segs=14,
        ),
    )

    # Selectable: shoulders (bilateral deltoids)
    sh_l = _build_ellipsoid(0.212, 1.40, 0.005, 0.058, 0.076, 0.064, lat_rings=8, segs=14, tilt_z=-0.25)
    sh_r = _build_ellipsoid(-0.212, 1.40, 0.005, 0.058, 0.076, 0.064, lat_rings=8, segs=14, tilt_z=0.25)
    parts["shoulders"] = ("muscle_selectable", *_mirror_parts([sh_l, sh_r]))

    # Selectable: biceps (+Z upper arm)
    bi_l = _build_ellipsoid(0.245, 1.24, 0.024, 0.040, 0.105, 0.034, lat_rings=8, segs=14, tilt_z=0.14)
    bi_r = _build_ellipsoid(-0.245, 1.24, 0.024, 0.040, 0.105, 0.034, lat_rings=8, segs=14, tilt_z=-0.14)
    parts["biceps"] = ("muscle_selectable", *_mirror_parts([bi_l, bi_r]))

    # Selectable: triceps (-Z upper arm)
    tri_l = _build_ellipsoid(0.245, 1.24, -0.024, 0.042, 0.105, 0.034, lat_rings=8, segs=14, tilt_z=0.14)
    tri_r = _build_ellipsoid(-0.245, 1.24, -0.024, 0.042, 0.105, 0.034, lat_rings=8, segs=14, tilt_z=-0.14)
    parts["triceps"] = ("muscle_selectable", *_mirror_parts([tri_l, tri_r]))

    # Selectable: forearms
    fa_l = _build_lofted_part(
        [
            (0.308, 0.87, 0.012, 0.026, 0.026),
            (0.295, 0.96, 0.010, 0.034, 0.034),
            (0.280, 1.06, 0.006, 0.042, 0.040),
            (0.268, 1.12, 0.002, 0.038, 0.038),
        ],
        segs=14,
    )
    fa_r = _build_lofted_part(
        [
            (-0.308, 0.87, 0.012, 0.026, 0.026),
            (-0.295, 0.96, 0.010, 0.034, 0.034),
            (-0.280, 1.06, 0.006, 0.042, 0.040),
            (-0.268, 1.12, 0.002, 0.038, 0.038),
        ],
        segs=14,
    )
    parts["forearms"] = ("muscle_selectable", *_mirror_parts([fa_l, fa_r]))

    # Selectable: glutes (-Z hips)
    gl_l = _build_ellipsoid(0.080, 0.87, -0.068, 0.072, 0.090, 0.056, lat_rings=8, segs=14)
    gl_r = _build_ellipsoid(-0.080, 0.87, -0.068, 0.072, 0.090, 0.056, lat_rings=8, segs=14)
    parts["glutes"] = ("muscle_selectable", *_mirror_parts([gl_l, gl_r]))

    # Selectable: quads (+Z thigh)
    qd_l = _build_ellipsoid(0.104, 0.67, 0.026, 0.066, 0.175, 0.054, lat_rings=8, segs=14, tilt_z=0.04)
    qd_r = _build_ellipsoid(-0.104, 0.67, 0.026, 0.066, 0.175, 0.054, lat_rings=8, segs=14, tilt_z=-0.04)
    parts["quads"] = ("muscle_selectable", *_mirror_parts([qd_l, qd_r]))

    # Selectable: hamstrings (-Z thigh)
    hm_l = _build_ellipsoid(0.102, 0.65, -0.030, 0.060, 0.155, 0.050, lat_rings=8, segs=14, tilt_z=0.04)
    hm_r = _build_ellipsoid(-0.102, 0.65, -0.030, 0.060, 0.155, 0.050, lat_rings=8, segs=14, tilt_z=-0.04)
    parts["hamstrings"] = ("muscle_selectable", *_mirror_parts([hm_l, hm_r]))

    # Selectable: calves (lower legs)
    cv_l = _build_lofted_part(
        [
            (0.104, 0.11, -0.005, 0.034, 0.036),
            (0.106, 0.24, -0.012, 0.046, 0.048),
            (0.106, 0.36, -0.014, 0.056, 0.056),
            (0.104, 0.47, 0.000, 0.048, 0.050),
        ],
        segs=14,
    )
    cv_r = _build_lofted_part(
        [
            (-0.104, 0.11, -0.005, 0.034, 0.036),
            (-0.106, 0.24, -0.012, 0.046, 0.048),
            (-0.106, 0.36, -0.014, 0.056, 0.056),
            (-0.104, 0.47, 0.000, 0.048, 0.050),
        ],
        segs=14,
    )
    parts["calves"] = ("muscle_selectable", *_mirror_parts([cv_l, cv_r]))

    return parts


def _compute_vertex_normals(verts: list[tuple[float, float, float]], tris: list[tuple[int, int, int]]) -> list[tuple[float, float, float]]:
    accum = [[0.0, 0.0, 0.0] for _ in verts]
    for i0, i1, i2 in tris:
        e1 = _sub(verts[i1], verts[i0])
        e2 = _sub(verts[i2], verts[i0])
        fn = _cross(e1, e2)
        for idx in (i0, i1, i2):
            accum[idx][0] += fn[0]
            accum[idx][1] += fn[1]
            accum[idx][2] += fn[2]
    return [_normalize((n[0], n[1], n[2])) for n in accum]


def _fmt(val: float) -> str:
    rounded = round(val, 5)
    if rounded == 0.0:
        rounded = 0.0
    return f"{rounded:.5f}"


def write_obj_and_mtl(obj_path: Path) -> None:
    obj_path.parent.mkdir(parents=True, exist_ok=True)
    mtl_path = obj_path.with_suffix(".mtl")

    mtl_lines = [
        "# Step Track 3D Body Map Materials",
        "newmtl muscle_selectable",
        "Kd 0.46 0.52 0.56",
        "Ka 0.12 0.14 0.16",
        "Ks 0.22 0.22 0.22",
        "Ns 28.0",
        "d 1.0",
        "",
        "newmtl body_structural",
        "Kd 0.24 0.27 0.30",
        "Ka 0.08 0.09 0.10",
        "Ks 0.10 0.10 0.10",
        "Ns 16.0",
        "d 1.0",
        "",
        "newmtl cardio_emblem",
        "Kd 0.78 0.24 0.30",
        "Ka 0.20 0.06 0.08",
        "Ks 0.35 0.20 0.20",
        "Ns 40.0",
        "d 1.0",
        "",
    ]
    mtl_path.write_text("\n".join(mtl_lines), encoding="utf-8", newline="\n")

    parts = _build_body_parts()
    obj_lines = [
        "# Step Track Sculpted 3D Anatomical Body Mesh",
        f"mtllib {mtl_path.name}",
    ]

    v_offset = 1
    for region in ALL_REGIONS:
        material, verts, tris = parts[region]
        normals = _compute_vertex_normals(verts, tris)
        obj_lines.append(f"o {region}")
        obj_lines.append(f"usemtl {material}")
        for vx, vy, vz in verts:
            obj_lines.append(f"v {_fmt(vx)} {_fmt(vy)} {_fmt(vz)}")
        for nx, ny, nz in normals:
            obj_lines.append(f"vn {_fmt(nx)} {_fmt(ny)} {_fmt(nz)}")
        for a, b, c in tris:
            ia, ib, ic = a + v_offset, b + v_offset, c + v_offset
            obj_lines.append(f"f {ia}//{ia} {ib}//{ib} {ic}//{ic}")
        v_offset += len(verts)

    obj_path.write_text("\n".join(obj_lines) + "\n", encoding="utf-8", newline="\n")


def validate_obj(obj_path: Path) -> dict[str, int]:
    if not obj_path.is_file():
        raise FileNotFoundError(f"Missing OBJ file: {obj_path}")
    size = obj_path.stat().st_size
    if size <= 0 or size >= MAX_OBJ_BYTES:
        raise ValueError(f"OBJ size out of bounds: {size} bytes (limit < {MAX_OBJ_BYTES})")

    mtl_path = obj_path.with_suffix(".mtl")
    if not mtl_path.is_file():
        raise FileNotFoundError(f"Missing MTL file: {mtl_path}")

    mtl_names = {
        line.split()[1]
        for line in mtl_path.read_text(encoding="utf-8").splitlines()
        if line.startswith("newmtl ")
    }
    expected_mtls = {"muscle_selectable", "body_structural", "cardio_emblem"}
    if not expected_mtls <= mtl_names:
        raise ValueError(f"Missing materials in {mtl_path}: {expected_mtls - mtl_names}")

    verts: list[tuple[float, float, float]] = []
    normals: list[tuple[float, float, float]] = []
    groups: dict[str, dict] = {}
    current_group: str | None = None

    for line_no, raw_line in enumerate(obj_path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#") or line.startswith("mtllib "):
            continue
        tokens = line.split()
        cmd = tokens[0]
        if cmd == "o":
            current_group = tokens[1]
            if current_group in groups:
                raise ValueError(f"Duplicate group {current_group!r} at line {line_no}")
            groups[current_group] = {"mtls": set(), "tris": [], "v_indices": set()}
        elif cmd == "usemtl":
            if current_group is None:
                raise ValueError(f"usemtl outside object group at line {line_no}")
            if tokens[1] not in mtl_names:
                raise ValueError(f"Unknown material {tokens[1]!r} at line {line_no}")
            groups[current_group]["mtls"].add(tokens[1])
        elif cmd == "v":
            verts.append((float(tokens[1]), float(tokens[2]), float(tokens[3])))
        elif cmd == "vn":
            normals.append((float(tokens[1]), float(tokens[2]), float(tokens[3])))
        elif cmd == "f":
            if current_group is None:
                raise ValueError(f"Face outside object group at line {line_no}")
            face_v: list[int] = []
            for corner in tokens[1:]:
                v_part, _, vn_part = corner.partition("//")
                vi = int(v_part) - 1
                vni = int(vn_part) - 1 if vn_part else vi
                if not (0 <= vi < len(verts)):
                    raise ValueError(f"Vertex index out of range at line {line_no}: {vi + 1}")
                if not (0 <= vni < len(normals)):
                    raise ValueError(f"Normal index out of range at line {line_no}: {vni + 1}")
                face_v.append(vi)
                groups[current_group]["v_indices"].add(vi)
            for k in range(1, len(face_v) - 1):
                groups[current_group]["tris"].append((face_v[0], face_v[k], face_v[k + 1]))

    missing_groups = set(ALL_REGIONS) - set(groups.keys())
    if missing_groups:
        raise ValueError(f"Missing required o <region> groups: {sorted(missing_groups)}")

    total_tris = 0
    for region in ALL_REGIONS:
        g = groups[region]
        if len(g["mtls"]) != 1:
            raise ValueError(f"Group {region} must use exactly 1 material, got {g['mtls']}")
        if len(g["tris"]) < 12:
            raise ValueError(f"Group {region} has too few triangles: {len(g['tris'])}")
        total_tris += len(g["tris"])

        pts = [verts[i] for i in g["v_indices"]]
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        zs = [p[2] for p in pts]
        if max(xs) - min(xs) <= 1e-4 or max(ys) - min(ys) <= 1e-4 or max(zs) - min(zs) <= 1e-4:
            raise ValueError(f"Group {region} has degenerate bounding box")

        vol = _signed_volume(verts, g["tris"])
        if vol <= 0.0:
            raise ValueError(f"Group {region} has non-positive signed volume ({vol:.6f}); normals/winding invalid")

    return {
        "groups": len(groups),
        "vertices": len(verts),
        "triangles": total_tris,
        "bytes": size,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args(argv)

    if not args.verify_only:
        write_obj_and_mtl(args.output)

    stats = validate_obj(args.output)
    action = "Verified" if args.verify_only else "Generated and verified"
    print(f"{action} {args.output}: {stats['groups']} groups, {stats['vertices']} vertices, {stats['triangles']} triangles, {stats['bytes']} bytes")
    return 0


if __name__ == "__main__":
    sys.exit(main())
