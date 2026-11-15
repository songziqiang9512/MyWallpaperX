"""Real static-model ambient and emission pixels through the shared GPU harness."""

from __future__ import annotations

import itertools
import math
import unittest

from script.tests import test_scene_static_model_pipeline as model_fixture
from script.tests.test_scene_directional_shadow import SCENE, run_swift


ALBEDO = [0.2, 0.3, 0.4]
OPACITY = 0.75
MAX_HALF = 65504.0
MAX_FLOAT = 3.4028234663852886e38


def emission_vectors() -> list[dict]:
    vectors = [
        {
            "name": f"mask-{mask}-gain-{gain}-ambient-{light}-color-{color}",
            "albedo": ALBEDO,
            "maskAlpha": mask,
            "hasMask": True,
            "brightness": gain,
            "ambient": [0.0, 0.0, 0.0] if light == 0 else [0.4, 0.6, 0.8],
            "emissiveColor": [1.0, 1.0, 1.0] if color == 0 else [0.5, 0.25, 0.75],
            "opacity": OPACITY,
        }
        for mask, gain, light, color in itertools.product(
            [0.0, 0.25, 1.0], [0.0, 0.25, 1.0, 4.0, 10.0, 100000.0], range(2), range(2)
        )
    ]
    def extra(name, *, gain, albedo=ALBEDO, color=(1.0, 1.0, 1.0), ambient=(0.4, 0.6, 0.8),
              has_mask=True, fog_density=None):
        vectors.append({
            "name": name, "albedo": albedo, "maskAlpha": 1.0, "hasMask": has_mask,
            "brightness": gain, "ambient": ambient, "emissiveColor": color, "opacity": OPACITY,
            "fogDensity": fog_density, "fogColor": [0.125, 0.25, 0.5],
        })
    for gain in [1.0, 100000.0]:
        extra(f"black-albedo-gain-{gain}", gain=gain, albedo=[0.0, 0.0, 0.0])
        for light in range(2):
            extra(f"no-mask-gain-{gain}-ambient-{light}", gain=gain, has_mask=False,
                  ambient=[0.0, 0.0, 0.0] if light == 0 else [0.4, 0.6, 0.8])
    extra("final-premultiplied-storage-limit", gain=100000.0, albedo=[1.0, 1.0, 1.0])
    extra("max-float-zero-emissive-color", gain=MAX_FLOAT, color=[0.0, 0.0, 0.0])
    extra("max-float-black-albedo", gain=MAX_FLOAT, albedo=[0.0, 0.0, 0.0])
    extra("full-fog-extreme-emission", gain=1e30, color=[1e30, 1e30, 1e30], fog_density=1.0)
    extra("partial-fog-extreme-storage-limit", gain=1e30, color=[1e30, 1e30, 1e30], fog_density=0.5)
    extra("partial-fog-before-storage-limit", gain=100000.0, albedo=[1.0, 1.0, 1.0], fog_density=0.5)
    return vectors


def ambient_vectors() -> list[dict]:
    # Official fixed-unit-normal inputs (2026-10-09), half-gray albedo:
    # ambient-only bytes 0,32,64,96,128; sky-only endpoints/midpoint 128,64,0.
    cases = [
        (f"ambient-y-{y}", [math.sqrt(1-y*y), y, 0], [0.4, 0.6, 0.8], [0, 0, 0], a, 0)
        for y, a in [(-1, 0), (-0.5, 0.25), (0, 0.5), (0.5, 0.75), (1, 1)]
    ] + [
        (f"sky-y-{y}", [math.sqrt(1-y*y), y, 0], [0, 0, 0], [0.4, 0.6, 0.8], 0, sky)
        for y, sky in [(-1, 1), (0, 0.5), (1, 0)]
    ] + [
        ("mixed-y-zero", [1, 0, 0], [0.2, 0.4, 0.6], [0.6, 0.4, 0.2], 0.5, 0.5),
        ("ambient-z-plus1", [0, 0, 1], [0.4, 0.6, 0.8], [0, 0, 0], 0.5, 0),
    ]
    return [
        {"name": name, "normal": normal, "ambient": ambient, "skylight": sky,
         "ambientResponse": a, "skyResponse": k, "albedo": ALBEDO,
         "hasMask": False, "maskAlpha": 0, "emissiveColor": [1, 1, 1],
         "brightness": 0, "opacity": OPACITY}
        for name, normal, ambient, sky, a, k in cases
    ]


def distance_fog_vectors() -> list[dict]:
    # Official half-gray flat-quad probes: the halfway distance yields RGB 96,
    # while a constant .5 density yields 64. These are different contracts.
    # The harness pixel is at world (0, 0, .5); camera positions preserve the
    # independently specified distance, including an off-axis radial control.
    cases = [
        ("quarter", [0, 4, 0, 1], [0, 0, 1.5], 0.0625),
        ("half", [0, 2, 0, 1], [0, 0, 1.5], 0.25),
        ("three-quarter", [0, 4 / 3, 0, 1], [0, 0, 1.5], 0.5625),
        ("offset", [0.5, 1.5, 0, 1], [0, 0, 1.5], 0.25),
        ("double-distance", [0, 4, 0, 1], [0, 0, 2.5], 0.25),
        ("off-axis", [0, 2, 0, 1], [1, 0, 1.5], 0.5),
        ("before-start", [2, 4, 0.2, 0.8], [0, 0, 1.5], 0.2),
        ("after-end", [0, 0.5, 0.2, 0.8], [0, 0, 1.5], 0.8),
        ("density-endpoints", [0, 2, 0.2, 0.8], [0, 0, 1.5], 0.35),
    ]
    return [dict(
        name=f"distance-fog-{name}", albedo=[0.5, 0.5, 0.5], opacity=1,
        normal=[0, 1, 0], ambient=[1, 1, 1], ambientResponse=1,
        hasMask=False, maskAlpha=0, emissiveColor=[1, 1, 1], brightness=0,
        fogRange=interval, cameraPosition=camera, expectedFogDensity=density,
        fogColor=[0.125, 0.25, 0.5] if name == "density-endpoints" else [0, 0, 0],
    ) for name, interval, camera, density in cases]


def surface_vectors() -> list[dict]:
    # Frozen own-plane official U8 centers (WE 2.8.0.42, 2026-10-09).
    # Translate the known receiver/light/camera together by +.5Z to the
    # existing 1px harness plane; no BRDF expression is used as the oracle.
    cases = [
        ("H1-point-axis", "point", 0, .7, [0, 0, 2.5], [0, 0, 4.5], 54),
        ("spot-axis", "spot", 0, .7, [0, 0, 2.5], [0, 0, 4.5], 54),
        ("H2-point-oblique", "point", 0, .7, [1.6, 0, 1.7], [0, 0, 4.5], 31),
        ("H3-spot-view60", "spot", 0, .7, [0, 0, 2.5], [math.sqrt(12), 0, 2.5], 52),
        ("H8-roughness-half", "spot", 0, .5, [0, 0, 2.5], [0, 0, 4.5], 66),
        ("H9-roughness-one", "spot", 0, 1, [0, 0, 2.5], [0, 0, 4.5], 51),
        ("H10-metal-view60", "spot", 1, .7, [0, 0, 2.5], [math.sqrt(12), 0, 2.5], 25),
    ]
    rows = [dict(name=name, lamp=lamp, surface=[m, r], lightPosition=position,
        cameraPosition=camera, expectedByte=expected, albedo=[1, 1, 1], tint=[.5, .5, .5],
        ambient=[0, 0, 0], emissiveColor=[1, 1, 1], brightness=0, opacity=1,
        hasMask=False, maskAlpha=0) for name, lamp, m, r, position, camera, expected in cases]
    rows.append(dict(rows[1], name="gray128-white-tint-pair",
        albedo=[128/255]*3, tint=[1, 1, 1]))
    # Local preservation controls use the old project's center, not an official BRDF claim.
    rows.append(dict(rows[0], name="legacy-point-preserved", surface=None, expectedByte=49))
    # One axial point at d/R=.5. The legacy-response material has .30
    # unattenuated direct RGB; compare the profiled material against equal
    # incident energy from the already validated directional producer.
    for name, exponent, z, incident in (
        ("omitted", None, 5.5, .25), ("two", 2, 5.5, .25),
        ("gentle", .1, 5.5, .9330329915), ("steep", 5, 5.5, .03125),
        ("zero-inside", 0, 5.5, 1), ("zero-edge", 0, 10.5, 1),
        ("zero-outside", 0, 11.5, 1), ("gentle-outside", .1, 11.5, 0),
    ):
        point = dict(rows[0], lightPosition=[0, 0, z], lightExponent=exponent)
        rows.append(dict(point, name=f"point-falloff-{name}", surface=None,
            expectedByte=.30 * incident * 255))
        if name in ("gentle", "steep"):
            direction = f"directional-falloff-{name}"
            rows.append(dict(point, name=f"profiled-point-falloff-{name}",
                expectedByte=None, equivalentIncidentEnergy=direction))
            rows.append(dict(point, name=direction, lamp="directional",
                lightIntensity=2 * incident, expectedByte=None))
    cone_midpoint = math.degrees(math.acos((math.cos(math.radians(20))
        + math.cos(math.radians(40))) / 2))
    for name, exponent, ratio, angle, cone in (
        ("omitted", None, .5, 0, 1), ("two", 2, .5, 0, 1),
        ("near", .54, .25, 0, 1), ("middle", .54, .5, 0, 1), ("far", .54, .75, 0, 1),
        ("linear", 1, .5, 0, 1), ("zero-inside", 0, .5, 0, 1),
        ("zero-edge", 0, 1, 0, 1), ("zero-outside", 0, 1.1, 0, 1),
        ("cone-transition", .54, .5, cone_midpoint, .5), ("cone-outside", .54, .5, 50, 0),
    ):
        remaining = max(0, 1-ratio)
        radial = 1 if exponent == 0 else (
            remaining**(2 if exponent is None else exponent) if remaining > 0 else 0)
        incident = radial * cone
        for profile in [None, [.14, 1]]:
            label = f"spot-falloff-{name}-{'surface' if profile else 'legacy'}"
            spot = dict(rows[0], name=label, lamp="spot", surface=profile,
                lightPosition=[0, 0, .5+10*ratio], lightExponent=exponent,
                spotDirection=[math.sin(math.radians(angle)), 0, -math.cos(math.radians(angle))],
                equivalentIncidentEnergy=label+"-reference", expectedByte=None)
            rows += [spot, dict(spot, name=label+"-reference", lamp="directional",
                lightIntensity=2*incident, equivalentIncidentEnergy=None)]
    for kind in ["point", "spot"]:
        for name, z, radius, incident in (
            ("nonzero-near", .50001, 10, 1),
            ("small-radius-inside", .50001, .00002, 1),
            ("small-radius-outside", .50001, .000005, 1),
            ("coincident", .5, 10, 0), ("large-edge", 100.5, 100, 1),
        ):
            label = f"distance-domain-{kind}-{name}"
            actual = dict(rows[0], name=label, lamp=kind, lightPosition=[0, 0, z],
                lightRadius=radius, lightExponent=0, expectedByte=None,
                equivalentIncidentEnergy=label+"-reference")
            rows += [actual, dict(actual, name=label+"-reference", lamp="directional",
                lightIntensity=2*incident, equivalentIncidentEnergy=None)]
    # The old directional preservation row inherited a surface profile while
    # asserting the legacy path. The official metallic single-variable probe
    # disproves that bypass; preserve the original 77 oracle on its nil domain.
    rows.append(dict(rows[0], name="directional-preserved", lamp="directional",
        surface=None, expectedByte=77))
    default_directional = dict(rows[-1], name="directional-default-preserved")
    del default_directional["surface"]
    rows.append(default_directional)
    # These axis fixtures place point/spot two units away at radius ten. Their
    # independently validated falloff is .64, so a directional intensity 1.28
    # supplies the same incident energy as intensity-two point/spot. Keep the
    # existing measured point/spot pixel oracles, rather than deriving a BRDF.
    for reference in ("H1-point-axis", "H9-roughness-one", "H10-metal-view60"):
        row = next(row for row in rows if row["name"] == reference)
        rows.append(dict(row, name=f"directional-{reference}", lamp="directional",
            lightIntensity=1.28, equivalentIncidentEnergy=reference))
    neutral = next(row for row in rows if row["name"] == "directional-H9-roughness-one")
    # Retain an interior metallic declaration matching the real author input;
    # its response must differ from zero, not just from the metallic endpoint.
    rows.append(dict(neutral, name="directional-metallic-point14", surface=[.14, 1],
        equivalentIncidentEnergy=None, expectedByte=None,
        materialResponseReference=neutral["name"]))
    rows.append(dict(neutral, name="directional-nil-at-same-energy", surface=None,
        equivalentIncidentEnergy=None, expectedByte=49))
    # Reproduced black output from early half(100000), despite a finite
    # metallic surface response. This checks storage safety, not official HDR parity.
    rows.append(dict(rows[0], name="metal-hdr-finite-response", surface=[1, .7],
        tint=[1, 1, 1], materialBrightness=100000, usesHDR=True, finiteSurface=True,
        expectedByte=108))
    rows.append(dict(rows[-1], name="directional-metal-hdr-finite-response",
        lamp="directional", lightIntensity=1.28,
        equivalentIncidentEnergy="metal-hdr-finite-response"))
    for profile in (None, [0, .7]):
        rows.append(dict(rows[0], name=f"directional-unlit-profile-{profile is not None}",
            lamp="directional", surface=profile, receivesLighting=False,
            albedo=ALBEDO, tint=[1, 1, 1], opacity=OPACITY, lightIntensity=100,
            ambient=[20, 30, 40], expectedByte=None,
            expectedUnlitPixel=[0.15, 0.225, 0.3, OPACITY]))
    # Scale only the actual lamp and emissive color inversely; black albedo
    # removes additive emission so their common finite pixel needs no BRDF oracle.
    for name, color, intensity, reference in (
        ("hdr-gain-factor-overflow", 3e38, 1e-34, "hdr-gain-factor-safe-control"),
        ("hdr-gain-factor-safe-control", 3e37, 1e-33, None),
    ):
        rows.append(dict(rows[0], name=name, lamp="directional", surface=[0, .7],
            albedo=[0, 0, 0], tint=[1, 1, 1], opacity=1, ambient=[0, 0, 0],
            hasMask=True, maskAlpha=1, brightness=3, usesHDR=True,
            emissiveColor=[color, 0, 0], lightIntensity=intensity, expectedByte=None,
            equivalentIncidentEnergy=reference))
    for name, color, reference in (
        ("hdr-gain-zero-excess-large-color", 3e38, "hdr-gain-zero-excess-control"),
        ("hdr-gain-zero-excess-control", 0, None),
    ):
        rows.append(dict(rows[-1], name=name, brightness=1,
            emissiveColor=[color, 0, 0], lightIntensity=100,
            equivalentIncidentEnergy=reference))
    return rows


def surface_storage_vectors() -> list[dict]:
    # Positive finite author values; low/high HDR and view tint cover both
    # optional-profile states. The high tint has unequal endpoints and an
    # interior view weight, so legacy half mixing yields inf rather than inf-inf.
    base = surface_vectors()[0]
    return [dict(base, name=f"surface-storage-{profile}-{brightness}-{tint}",
        surface=[0, .7] if profile else None, materialBrightness=brightness,
        usesHDR=True, viewTint=[tint, 1], cameraPosition=[math.sqrt(12), 0, 2.5],
        storageBoundary=True, expectedByte=None)
        for profile, brightness, tint in itertools.product([False, True], [1, 100000], [1, 100000])]


def view_tint_vectors() -> list[dict]:
    # The center view points along +Z; these length-two normals give signed
    # facing +.5/-.5. Fixed hand-computed tint weights keep the oracle separate
    # from the shader: unmasked is linear; masked retains the prior exponent.
    base = dict(albedo=[.25]*3, normal=[math.sqrt(3), 0, 1],
        cameraPosition=[0, 0, 2.5], ambient=[0, 0, 0], receivesLighting=False,
        hasMask=False, maskAlpha=0, emissiveColor=[1, 1, 1], brightness=0,
        opacity=.5, viewTint=[.75, .5])
    rows = [dict(base, name=f"view-tint-{masked}-{exponent}", tintMask=masked,
                 viewExponent=exponent, expectedViewTint=weight)
            for masked, exponent, weight in [
                (False, 2, .625), (False, 4, .625),
                (True, 2, .5625), (True, 4, .515625)]]
    for exponent in (2, 4):
        rows.append(dict(base, name=f"view-tint-neutral-{exponent}",
            normal=[math.sqrt(3), 0, -1], viewTint=[.625, .625],
            tintMask=True, viewExponent=exponent, expectedViewTint=.625))
    rows.append(dict(rows[0], name="view-tint-back-facing", normal=[math.sqrt(3), 0, -1],
        expectedViewTint=.375))
    rows.append(dict(rows[0], name="renamed-tilted-surface", normal=[3*math.sqrt(3), 0, 3],
        cameraPosition=[0, 0, 8.5]))
    rows.append(dict(rows[0], name="view-tint-premultiplied-source", albedo=[.125]*3,
        albedoAlpha=.5, colorPremultiplied=True))
    rows.append(dict(rows[0], name="view-tint-layer-fade", layerAlpha=.5))
    return rows


def hdr_intermediate_vectors() -> list[dict]:
    base = dict(surface=None, receivesLighting=False, albedo=[1/255]*3,
        tint=[131072]*3, opacity=1/1024, ambient=[0, 0, 0], hasMask=False,
        maskAlpha=0, emissiveColor=[1, 1, 1], brightness=0)
    half_gray = [257/512]*3
    pairs = [
        ("texture", dict(albedo=[131072]*3, tint=[1/256]*3),
         dict(albedo=[1]*3, tint=[512]*3), [.5]*3, False),
        ("tint", {}, dict(albedo=[1]*3, tint=[514]*3), half_gray, False),
        ("masked-tint", dict(tintMask=True),
         dict(albedo=[1]*3, tint=[514]*3, tintMask=True), half_gray, False),
        ("late-view-fog", dict(tint=[32768]*3, viewTint=[1024, 1024], opacity=1/256,
            fogDensity=1023/1024, fogColor=[0, 0, 0]),
         dict(albedo=[1]*3, tint=[128.5]*3, viewTint=[1, 1], opacity=1/256,
            fogDensity=0, fogColor=[0, 0, 0]), half_gray, False),
        ("pma-small-positive", dict(albedo=[1/16384]*3, albedoAlpha=1/1048576,
            tint=[1]*3, opacity=1, colorPremultiplied=True, textureAlphaIsOpacity=True),
         dict(albedo=[64]*3, albedoAlpha=1/1048576, tint=[1]*3, opacity=1,
            textureAlphaIsOpacity=True), [1/16384]*3, False),
        ("pma-division", dict(albedo=[1.5]*3, albedoAlpha=1/65536, tint=[1]*3,
            opacity=1, colorPremultiplied=True, textureAlphaIsOpacity=True),
         dict(albedo=[1.5]*3, albedoAlpha=1/65536, tint=[1]*3, opacity=1,
            textureAlphaIsOpacity=True, hasMask=True, maskAlpha=1, brightness=65535), [1.5]*3, False),
        ("small-coverage", dict(albedo=[1]*3, tint=[67108864]*3, opacity=1/67108864),
         dict(albedo=[1]*3, tint=[1]*3, opacity=1), [1]*3, True),
    ]
    rows = []
    for name, actual, control, rgb, rgb_only in pairs:
        reference = f"hdr16-{name}-control"
        for suffix, changes in (("actual", actual), ("control", control)):
            row = dict(base)
            row.update(changes, name=f"hdr16-{name}-{suffix}", hdrIntermediate=True)
            alpha = row["opacity"] * (row.get("albedoAlpha", 1) if row.get("textureAlphaIsOpacity") else 1)
            row["expectedStoredAlpha"] = 0 if name == "small-coverage" and suffix == "actual" else alpha
            row["expectedUnlitPixel"] = [*rgb, row["expectedStoredAlpha"]]
            if suffix == "actual":
                row.update(hdrReference=reference, hdrCompareRGBOnly=rgb_only)
            rows.append(row)
    for name, changes, pixel in [
        ("straight-zero-alpha", dict(albedo=[.25]*3, albedoAlpha=0, tint=[1]*3, opacity=1), [.25]*3+[1]),
        ("masked-zero-alpha", dict(albedo=[.25]*3, albedoAlpha=0, tintMask=True,
            tint=[131072]*3, opacity=1), [.25]*3+[1]),
        ("pma-zero", dict(albedo=[1.5]*3, albedoAlpha=0, colorPremultiplied=True,
            textureAlphaIsOpacity=True, tint=[1]*3, opacity=1), [0]*4),
        ("ordinary", dict(albedo=[.25, .5, 1], tint=[2, 1, .5], opacity=.5), [.25]*3+[.5]),
        ("brightness-producer", dict(tint=[1]*3, materialBrightness=131072, usesHDR=True), half_gray+[1/1024]),
    ]:
        row = {**base, **changes, "name": "hdr16-"+name, "hdrIntermediate": True,
               "expectedUnlitPixel": pixel, "expectedStoredAlpha": pixel[3]}
        if name == "brightness-producer": row["hdrReference"] = "hdr16-tint-control"
        rows.append(row)
    return rows


def zero_surface_vectors() -> list[dict]:
    # Exact-zero direct specular is a delta, not a finite raster lobe. The
    # remaining expectation uses only independent Fresnel, diffuse and lamp
    # geometry; it contains no GGX distribution or visibility expression.
    base = {key: value for key, value in surface_vectors()[0].items() if key != "expectedByte"}
    rows = []
    for lamp, metallic in itertools.product(["point", "spot", "directional"], [0, 1]):
        rows.append(dict(base, name=f"polished-{lamp}-{metallic}", lamp=lamp,
            surface=[metallic, 0], albedo=[.5, .25, .125], tint=[1, 1, 1],
            lightIntensity=1.28 if lamp == "directional" else 2))
    rows.append(dict(rows[0], name="renamed-angled-mineral", lightPosition=[.9, 0, .6],
        cameraPosition=[-.9, 0, .6]))
    rows.append(dict(rows[1], name="polished-metal-keeps-covered-ambient-emission",
        opacity=.25, ambient=[.4, .6, .8], hasMask=True, maskAlpha=.5,
        emissiveColor=[.25, .5, 1], brightness=2))
    for row in rows:
        toward_light = ([0, 0, 1] if row["lamp"] == "directional" else
                        [x-y for x, y in zip(row["lightPosition"], [0, 0, .5])])
        toward_view = [x-y for x, y in zip(row["cameraPosition"], [0, 0, .5])]
        length = math.sqrt(sum(x*x for x in toward_light))
        unit = lambda v: [x/math.sqrt(sum(y*y for y in v)) for x in v]
        light, view = unit(toward_light), unit(toward_view)
        halfway = unit([x+y for x, y in zip(light, view)])
        voh = max(0, min(1, sum(x*y for x, y in zip(view, halfway))))
        no_l = max(0, light[2])
        attenuation = 1 if row["lamp"] == "directional" else max(0, 1-length/10)**2
        metallic = row["surface"][0]
        row["zeroDirect"] = []
        for color in row["albedo"]:
            f0 = .04*(1-metallic)+color*metallic
            fresnel = f0+(1-f0)*(1-voh)**5
            row["zeroDirect"].append(color*(1-metallic)*(1-fresnel)*no_l
                * row["lightIntensity"]*attenuation/math.pi)
    return rows


def expected_pixel(vector: dict) -> list[float]:
    # The additive material contract was established by controlled official
    # renders; known-normal cases carry measured response weights independently.
    if "expectedUnlitPixel" in vector:
        return vector["expectedUnlitPixel"]
    mask = vector["maskAlpha"] if vector["hasMask"] else 0.0
    albedo = vector["albedo"]
    if vector.get("colorPremultiplied"):
        albedo = [value/vector["albedoAlpha"] for value in albedo]
    radiance = [
        value * ((ambient * vector.get("ambientResponse", 0.5)
                  + sky * vector.get("skyResponse", 0.5)
                  if vector.get("receivesLighting", True) else 1)
                 + color * mask * vector["brightness"])
        for value, ambient, sky, color in zip(
            albedo, vector["ambient"], vector.get("skylight", [0, 0, 0]), vector["emissiveColor"]
        )
    ]
    radiance = [value+direct for value, direct in zip(radiance, vector.get("zeroDirect", [0, 0, 0]))]
    radiance = [value*vector.get("expectedViewTint", 1) for value in radiance]
    density = vector.get("expectedFogDensity", vector.get("fogDensity"))
    if density is not None:
        radiance = [lit * (1.0 - density) + fog * density
                    for lit, fog in zip(radiance, vector["fogColor"])]
    coverage = vector["opacity"]*vector.get("layerAlpha", 1)
    return [min(MAX_HALF, max(0.0, lit * coverage)) for lit in radiance] + [coverage]


def half_storage_tolerance(expected: float) -> float:
    # Two Float16 ULPs allow texture sample and final storage rounding without
    # allowing a gain plateau, an emission mix, or early storage clamping.
    exponent = math.floor(math.log2(abs(expected))) if expected else -14
    return 2.0 ** (max(-14, exponent) - 9)


PIXEL_MAIN = r'''
@main enum StaticModelEmissionProbe {
    static func main() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            print("{\"metalUnavailable\":true}")
            return
        }
        let pipeline = SceneStaticModelPipeline(device: device, colorPixelFormat: .rgba16Float)!
        let inputs = try JSONSerialization.jsonObject(with: Data(
            contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])
        )) as! [[String: Any]]
        func vector(_ values: [Double]) -> SIMD3<Float> {
            SIMD3(Float(values[0]), Float(values[1]), Float(values[2]))
        }
        func texture(_ rgb: [Double], alpha: Float) -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba32Float, width: 1, height: 1, mipmapped: false
            )
            descriptor.storageMode = .shared
            descriptor.usage = .shaderRead
            let result = device.makeTexture(descriptor: descriptor)!
            var value = [Float(rgb[0]), Float(rgb[1]), Float(rgb[2]), alpha]
            value.withUnsafeMutableBytes {
                result.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0,
                    withBytes: $0.baseAddress!, bytesPerRow: 16)
            }
            return result
        }
        let positions: [SIMD3<Float>] = [
            SIMD3(-1, -1, 0.5), SIMD3(1, -1, 0.5), SIMD3(1, 1, 0.5), SIMD3(-1, 1, 0.5),
        ]
        let commandBuffer = queue.makeCommandBuffer()!
        var buffers: [MTLBuffer] = []
        var boundaries: [String: (encoded: Bool, peer: Bool, depth: MTLBuffer)] = [:]
        for input in inputs {
            let drawBoundary = input["drawBoundary"] as? Bool ?? false
            let width = drawBoundary ? 2 : 1
            let vertices = positions.map {
                SceneMdlStaticModel.Vertex(position: $0, normal: vector(input["normal"] as? [Double] ?? [0, 0, 1]),
                    tangent: SIMD4(1, 0, 0, 1), uv: SIMD2(0.5, 0.5))
            }
            let mesh = pipeline.makeMesh(model: SceneStaticModelFixture.model(vertices: vertices, indices: [0, 1, 2, 0, 2, 3]))!
            let albedo = texture(input["albedo"] as! [Double],
                alpha: Float(input["albedoAlpha"] as? Double ?? 1))
            let mask: MTLTexture? = (input["hasMask"] as! Bool)
                ? texture([0, 0, 0], alpha: Float(input["maskAlpha"] as! Double)) : nil
            let colorDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba16Float, width: width, height: 1, mipmapped: false
            )
            colorDescriptor.storageMode = .private
            colorDescriptor.usage = .renderTarget
            let output = device.makeTexture(descriptor: colorDescriptor)!
            let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .depth32Float, width: width, height: 1, mipmapped: false
            )
            depthDescriptor.storageMode = .private
            depthDescriptor.usage = .renderTarget
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = output
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            pass.depthAttachment.texture = device.makeTexture(descriptor: depthDescriptor)!
            pass.depthAttachment.loadAction = .clear
            pass.depthAttachment.storeAction = drawBoundary ? .store : .dontCare
            pass.depthAttachment.clearDepth = 0
            let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)!
            if drawBoundary { encoder.setScissorRect(.init(x: 0, y: 0, width: 1, height: 1)) }
            let rawBrightness = input["materialBrightness"] as? Double
                ?? (input["materialBrightness"] as? String).flatMap(Double.init) ?? 1
            let material = SceneStaticModelMaterial(
                color: vector(input["tint"] as? [Double] ?? [1, 1, 1]), opacity: Float(input["opacity"] as! Double),
                receivesLighting: input["receivesLighting"] as? Bool ?? true,
                textureAlphaIsOpacity: input["textureAlphaIsOpacity"] as? Bool ?? false,
                textureAlphaIsTintMask: input["tintMask"] as? Bool ?? false,
                emissiveColor: vector(input["emissiveColor"] as! [Double]),
                emissiveBrightness: Float(input["brightness"] as! Double),
                brightness: Float(rawBrightness),
                usesHDRBrightness: input["usesHDR"] as? Bool ?? false,
                viewTint: (input["viewTint"] as? [Double]).map {
                    .init(front: SIMD3(repeating: Float($0[0])),
                          back: SIMD3(repeating: Float($0[1])),
                          exponent: Float(input["viewExponent"] as? Double ?? 1.5),
                          usesDynamicBackColor: false)
                },
                surfaceProfile: (input["surface"] as? [Double]).map {
                    .init(metallic: Float($0[0]), roughness: Float($0[1]))
                }, cullMode: .none
            )
            let lamp = input["lamp"] as? String
            let lightIntensity = Float(input["lightIntensity"] as? Double ?? 2)
            let lightRadius = Float(input["lightRadius"] as? Double ?? 10)
            let lightPosition = vector(input["lightPosition"] as? [Double] ?? [0, 0, 2.5])
            var lighting = SceneLightSnapshot(
                ambient: vector(input["ambient"] as! [Double]),
                skylight: vector(input["skylight"] as? [Double] ?? [0, 0, 0]),
                directional: lamp == "directional" ? [.init(
                    directionTowardLight: SIMD3(0, 0, 1), color: SIMD3(repeating: 1), intensity: lightIntensity
                )] : [],
                point: lamp == "point" ? [.init(position: lightPosition,
                    color: SIMD3(repeating: 1), intensity: lightIntensity, radius: lightRadius,
                    falloffExponent: Float(input["lightExponent"] as? Double ?? 2))] : [],
                spot: lamp == "spot" ? [.init(position: lightPosition,
                    directionFromLight: vector(input["spotDirection"] as? [Double] ?? [0, 0, -1]),
                    color: SIMD3(repeating: 1), intensity: lightIntensity,
                    radius: lightRadius, innerConeCosine: cos(Float.pi/9),
                    outerConeCosine: cos(Float.pi*2/9), outerConeDegrees: 40,
                    falloffExponent: Float(input["lightExponent"] as? Double ?? 2))] : [],
                overflowCount: 0
            )
            if let density = input["fogDensity"] as? Double {
                let fogColor = vector(input["fogColor"] as! [Double])
                lighting.distanceFogColor = SIMD4(fogColor, 1)
                lighting.distanceFogRange = SIMD4(0, 20, Float(density), Float(density))
            }
            if let range = input["fogRange"] as? [Double] {
                lighting.distanceFogColor = SIMD4(vector(input["fogColor"] as! [Double]), 1)
                lighting.distanceFogRange = SIMD4(Float(range[0]), Float(range[1]), Float(range[2]), Float(range[3]))
            }
            let encoded = pipeline.draw(
                mesh: mesh, texture: albedo,
                colorTextureIsPremultiplied: input["colorPremultiplied"] as? Bool ?? false,
                materialMap: mask.map { .init(texture: $0, textureFrame: .identity, sampling: .linearClamp, components: 8) }, modelMatrix: matrix_identity_float4x4,
                viewProjection: matrix_identity_float4x4,
                cameraPosition: vector(input["cameraPosition"] as? [Double] ?? [0, 0, 10]),
                textureFrame: .identity, sampling: .linearClamp,
                layerAlpha: Float(input["layerAlpha"] as? Double ?? 1),
                material: material, lighting: lighting, writesDepth: true, frameEpoch: 1,
                commandBuffer: commandBuffer, encoder: encoder
            )
            if !drawBoundary { precondition(encoded) }
            var peerEncoded = false
            if drawBoundary {
                encoder.setScissorRect(.init(x: 1, y: 0, width: 1, height: 1))
                let peer = SceneStaticModelMaterial(color: SIMD3(repeating: 1), opacity: 1,
                    receivesLighting: false, textureAlphaIsOpacity: false, textureAlphaIsTintMask: false,
                    emissiveColor: .zero, emissiveBrightness: 0, brightness: 1,
                    usesHDRBrightness: false, viewTint: nil, cullMode: .none)
                peerEncoded = pipeline.draw(mesh: mesh, texture: texture([0, 0, 1], alpha: 1),
                    colorTextureIsPremultiplied: false, modelMatrix: matrix_identity_float4x4,
                    viewProjection: matrix_identity_float4x4, cameraPosition: SIMD3(0, 0, 10),
                    textureFrame: .identity, sampling: .linearClamp, layerAlpha: 1,
                    material: peer, lighting: lighting, writesDepth: true, encoder: encoder)
            }
            encoder.endEncoding()
            let buffer = device.makeBuffer(length: 256, options: .storageModeShared)!
            let blit = commandBuffer.makeBlitCommandEncoder()!
            blit.copy(from: output, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: .init(x: 0, y: 0, z: 0), sourceSize: .init(width: width, height: 1, depth: 1),
                to: buffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
            if drawBoundary {
                let depthBuffer = device.makeBuffer(length: 256, options: .storageModeShared)!
                blit.copy(from: pass.depthAttachment.texture!, sourceSlice: 0, sourceLevel: 0,
                    sourceOrigin: .init(x: 0, y: 0, z: 0), sourceSize: .init(width: 2, height: 1, depth: 1),
                    to: depthBuffer, destinationOffset: 0, destinationBytesPerRow: 256, destinationBytesPerImage: 256)
                boundaries[input["name"] as! String] = (encoded, peerEncoded, depthBuffer)
            }
            blit.endEncoding()
            buffers.append(buffer)
        }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        let completed = commandBuffer.status == .completed && commandBuffer.error == nil
        let rows = zip(inputs, buffers).map { input, buffer -> [String: Any] in
            let pixel = buffer.contents().bindMemory(to: UInt16.self, capacity: 8)
            let channels = (0..<4).map {
                Float(Float16(bitPattern: pixel[$0]))
            }
            var result: [String: Any] = ["name": input["name"]!, "pixel": channels.map {
                $0.isFinite ? $0 as Any : String(describing: $0) as Any
            }, "completed": completed]
            if let boundary = boundaries[input["name"] as! String] {
                result["encoded"] = boundary.encoded; result["peerEncoded"] = boundary.peer
                result["peerPixel"] = (4..<8).map { Float(Float16(bitPattern: pixel[$0])) }
                let depths = boundary.depth.contents().bindMemory(to: Float.self, capacity: 2)
                result["depth"] = depths[0]; result["peerDepth"] = depths[1]
            }
            return result
        }
        print(String(decoding: try JSONSerialization.data(
            withJSONObject: ["rows": rows], options: [.sortedKeys]
        ), as: UTF8.self))
    }
}
'''


class SceneStaticModelEmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        sources = [getattr(model_fixture, name) for name in [
            "MODEL_SOURCE", "SAMPLING_SOURCE", "UV_TRANSFORM_SOURCE", "DIRECTIONAL_LIGHT_SOURCE",
            "POINT_LIGHT_SOURCE", "TUBE_LIGHT_SOURCE", "SPOT_LIGHT_SOURCE", "LIGHT_SOURCE", "VISIBILITY_SOURCE", "DYNAMIC_SNAPSHOT_SOURCE",
            "DYNAMIC_LAYER_VALUES_SOURCE", "PERFORMANCE_COUNTER_SOURCE", "MATERIAL_SOURCE", "PIPELINE_SOURCE", "SHADOW_SOURCE",
        ]]
        sources += [
            *model_fixture.MODEL_SUPPORT_SOURCES,
            SCENE / "Runtime/Frame/SceneStaticModelMaterialBindings.swift",
            SCENE / "Resources/Textures/SceneResourceBudget.swift",
        ]
        cls.vectors = (emission_vectors() + ambient_vectors() + distance_fog_vectors()
                       + surface_vectors() + surface_storage_vectors() + zero_surface_vectors()
                       + view_tint_vectors() + hdr_intermediate_vectors())
        cls.report = run_swift(
            sources, "import Foundation\nimport Metal\nimport simd\n" + model_fixture.LIGHTING_STUB + PIXEL_MAIN,
            label="model-emission", metal_sources=[model_fixture.METAL_SOURCE], input_value=cls.vectors,
        )

    def test_matrix_completes_with_finite_premultiplied_pixels(self):
        rows = self.report["rows"]
        self.assertEqual(len(rows), len(self.vectors))
        for vector, row in zip(self.vectors, rows):
            with self.subTest(case=vector["name"]):
                self.assertEqual(row["name"], vector["name"])
                self.assertTrue(row["completed"])
                self.assertEqual(len(row["pixel"]), 4)
                self.assertTrue(all(math.isfinite(float(value)) for value in row["pixel"]))
                self.assertEqual(row["pixel"][3], vector.get("expectedStoredAlpha",
                    vector["opacity"]*vector.get("layerAlpha", 1)))

    def test_additive_emission_pixels_match_numeric_contract(self):
        for vector, row in zip(self.vectors, self.report["rows"]):
            if "expectedByte" in vector and "expectedUnlitPixel" not in vector:
                continue
            for channel, (actual, expected) in enumerate(zip(row["pixel"], expected_pixel(vector))):
                with self.subTest(case=vector["name"], channel=channel):
                    actual = float(actual)
                    self.assertTrue(math.isfinite(actual), row)
                    self.assertAlmostEqual(actual, expected, delta=half_storage_tolerance(expected))

    def test_static_surface_response_matches_frozen_center_observations(self):
        for vector, row in zip(self.vectors, self.report["rows"]):
            if vector.get("expectedByte") is None:
                continue
            with self.subTest(case=vector["name"]):
                if vector.get("finiteSurface"):
                    self.assertTrue(all(math.isfinite(float(v)) and float(v) > 0 for v in row["pixel"][:3]))
                for actual in row["pixel"][:3]:
                    self.assertLessEqual(abs(float(actual)*255-vector["expectedByte"]), 1)

    def test_directional_profile_matches_incident_energy_and_preserves_legacy(self):
        by_name = {row["name"]: row for row in self.report["rows"]}
        for vector in self.vectors:
            reference = vector.get("equivalentIncidentEnergy")
            if reference is None:
                continue
            with self.subTest(case=vector["name"]):
                for actual, expected in zip(by_name[vector["name"]]["pixel"], by_name[reference]["pixel"]):
                    self.assertAlmostEqual(float(actual), float(expected),
                        delta=half_storage_tolerance(float(expected)))
        self.assertEqual(by_name["directional-preserved"]["pixel"],
            by_name["directional-default-preserved"]["pixel"])
        metallic = by_name["directional-metallic-point14"]["pixel"]
        neutral = by_name["directional-H9-roughness-one"]["pixel"]
        for actual, reference in zip(metallic[:3], neutral[:3]):
            self.assertGreater(float(actual), 0)
            self.assertLess(float(actual), float(reference))
        for name in ["hdr-gain-factor-safe-control", "hdr-gain-zero-excess-control"]:
            safe_gain = float(by_name[name]["pixel"][0])
            self.assertGreater(safe_gain, 1)
            self.assertLess(safe_gain, MAX_HALF)

    def test_finite_surface_storage_profile_and_legacy_boundaries(self):
        # The unmasked center has facing .5: front=100000/back=1 gives
        # 50000.5, replacing the old exponent/early-half-overflow expectation.
        legacy = {(1, 1): 49/255, (1, 100000): (49/255)*50000.5,
                  (100000, 1): 19200, (100000, 100000): MAX_HALF}
        for vector, row in zip(self.vectors, self.report["rows"]):
            if not vector.get("storageBoundary"):
                continue
            with self.subTest(case=vector["name"]):
                for channel in row["pixel"][:3]:
                    actual = float(channel)
                    self.assertTrue(math.isfinite(actual) and actual > 0)
                    self.assertLessEqual(actual, MAX_HALF)
                    if vector["surface"] is None:
                        expected = legacy[(vector["materialBrightness"], vector["viewTint"][0])]
                        self.assertAlmostEqual(actual, expected, delta=half_storage_tolerance(expected))

    def test_view_tint_mask_selects_exponent_and_keeps_signed_facing(self):
        pixels = {row["name"]: row["pixel"] for row in self.report["rows"]}
        linear = pixels["view-tint-False-2"]
        for name in ("view-tint-False-4", "renamed-tilted-surface", "view-tint-premultiplied-source"):
            with self.subTest(case=name):
                self.assertEqual(pixels[name], linear)
        self.assertNotEqual(pixels["view-tint-True-2"][:3], pixels["view-tint-True-4"][:3])
        self.assertEqual(pixels["view-tint-neutral-2"], pixels["view-tint-neutral-4"])
        self.assertLess(pixels["view-tint-back-facing"][0], linear[0])
        self.assertEqual(pixels["view-tint-layer-fade"], [value*.5 for value in linear])

    def test_hdr_intermediates_match_independent_safe_controls(self):
        pixels = {row["name"]: row["pixel"] for row in self.report["rows"]}
        for vector in self.vectors:
            if not vector.get("hdrIntermediate"):
                continue
            actual = pixels[vector["name"]]
            self.assertTrue(all(math.isfinite(float(value)) for value in actual), vector["name"])
            self.assertEqual(actual, vector["expectedUnlitPixel"], vector["name"])
            if reference := vector.get("hdrReference"):
                count = 3 if vector.get("hdrCompareRGBOnly") else 4
                self.assertEqual(actual[:count], pixels[reference][:count], vector["name"])
