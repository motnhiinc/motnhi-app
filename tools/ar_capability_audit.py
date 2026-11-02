#!/usr/bin/env python3
"""Fetch pinned SceneView source evidence and Apple documentation (no device probes)."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import urllib.error
import urllib.request
import zipfile

VERSION = "4.18.0"
SPECS = {
    "sceneview": {
        "node/ModelNode.kt": r"autoAnimate:|if \(autoAnimate|for \(i in 0 until animator.animationCount|fun playAnimation\(animationName|animator.applyAnimation",
        "loaders/ModelLoader.kt": r"suspend fun loadModel\(|suspend fun loadModelInstance\(|withContext\(Dispatchers.Main\)|suspend fun loadResourcesSuspended",
        "utils/File.kt": r"suspend fun.*loadFileBuffer|withContext\(Dispatchers.IO\)",
        "SceneFactories.kt": r"fun createMainLight|castShadows\(true\)",
        "SceneScope.kt": r"fun NodeLifecycle\(|node.destroy\(\)",
    },
    "arsceneview": {
        "ARScene.kt": r"depthMode: Config.DepthMode =|val lightEstimator =|arPlaneRenderer.isEnabled = planeRenderer|cameraStream\?\.isDepthOcclusionEnabled =|lightEstimator\?\.update\(|estimation.mainLight|environmentalHdr|config.lightEstimationMode =|scene.indirectLight = newIbl|estimation.irradiance\?\.let|estimation.reflections\?\.let",
        "camera/ARCameraStream.kt": r"var isDepthOcclusionEnabled =|isDepthOcclusionEnabled ->|session.config.depthMode|acquireDepthImage16Bits",
        "scene/PlaneRenderer.kt": r"override var isEnabled =|override var isVisible =|override var isShadowReceiver =|if \(isEnabled\)",
        "PlaneVisualizer.kt": r"fun setEnabled\(|isEnabled = enabled|if \(!isEnabled|isShadowReceiver &&",
        "node/AnchorNode.kt": r"field.detach\(\)|override fun destroy\(|detachAnchor\(\)",
        "ARSceneScope.kt": r"fun AnchorNode\(|node.destroy\(\)|anchorNode.destroy\(\)",
        "light/LightEstimator.kt": r"var isEnabled =|LightEstimationMode.AMBIENT_INTENSITY ->|LightEstimationMode.ENVIRONMENTAL_HDR ->",
    },
}
APPLE = [
    "realitykit/arview/renderoptions-swift.struct/disablegroundingshadows",
    "realitykit/arview/renderoptions-swift.struct/disablepersonocclusion",
    "realitykit/arview/environment-swift.struct/sceneunderstanding-swift.struct/options-swift.struct/occlusion",
    "arkit/arconfiguration/framesemantics-swift.property",
    "arkit/arworldtrackingconfiguration/scenereconstruction",
    "arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:)",
    "arkit/arconfiguration/supportsframesemantics(_:)",
]


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as response:
        return response.read()


def audit():
    report = {"sceneview_version": VERSION, "sceneview": [], "apple": []}
    for artifact, specs in SPECS.items():
        url = f"https://repo.maven.apache.org/maven2/io/github/sceneview/{artifact}/{VERSION}/{artifact}-{VERSION}-sources.jar"
        data = fetch(url)
        entry = {"artifact": artifact, "url": url, "sha256": hashlib.sha256(data).hexdigest(), "files": []}
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            for suffix, pattern in specs.items():
                names = [n for n in archive.namelist() if n.endswith('/' + suffix)]
                if not names:
                    entry["files"].append({"suffix": suffix, "status": "not_found"})
                    continue
                for name in names:
                    source = archive.read(name)
                    lines = source.decode().splitlines()
                    selected = set()
                    for i, line in enumerate(lines):
                        if re.search(pattern, line):
                            selected.update(range(max(0, i - 2), min(len(lines), i + 6)))
                    if not selected:
                        raise ValueError(f"No evidence matches for {artifact}: {name}; review source changes")
                    entry["files"].append({"path": name, "sha256": hashlib.sha256(source).hexdigest(),
                                            "evidence": [{"line": i + 1, "text": lines[i]} for i in sorted(selected)]})
        report["sceneview"].append(entry)
    for page in APPLE:
        url = "https://developer.apple.com/tutorials/data/documentation/" + page + ".json"
        try:
            data = fetch(url)
        except urllib.error.HTTPError as error:
            report["apple"].append({"data_url": url, "status": "unavailable", "http_status": error.code})
            continue
        doc = json.loads(data)
        report["apple"].append({"url": "https://developer.apple.com/documentation/" + page,
                                "data_url": url, "sha256": hashlib.sha256(data).hexdigest(),
                                "abstract": doc.get("abstract"), "content": doc.get("primaryContentSections"),
                                "platforms": doc.get("metadata", {}).get("platforms")})
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(audit(), indent=2) + "\n")
