#!/usr/bin/env python3
"""Copy pinned public agent examples from local clones into the test-only corpus.

No upstream setup scripts are executed. Original metadata and licenses are kept.
The corpus is outside Ohm's force-app package and is not part of its deployment.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
RECIPES = "force-app/main/02_actionConfiguration/"
SOURCES = [
    ("forcedotcom/afdx-pro-code-testdrive", "5fc6eadd1d19ae79097b4d5c9d24310f5ca0e128", "Apache-2.0", [
        "LICENSE.txt", "README.md", "sfdx-project.json", ".forceignore",
        "force-app", "config", "data-import",
    ]),
    ("trailheadapps/agent-script-recipes", "ac5ccac8f675153035370abbdce174e2b769c89c", "Apache-2.0", [
        "LICENSE.md", "README.md", "sfdx-project.json", ".forceignore", "config",
        RECIPES + "actionDefinitions", RECIPES + "actionChaining",
        RECIPES + "promptTemplateActions",
    ]),
    ("trailheadapps/coral-cloud", "d473624615907d015a7c1c2c339f101e732ecb7a", "CC0-1.0", [
        "LICENSE.md", "README.md", "sfdx-project.json", ".forceignore", "config",
        "cc-base-app", "cc-employee-app", "data",
        "cc-service-app/main/default/bots",
        "cc-service-app/main/default/genAiPlannerBundles",
        "cc-service-app/main/default/genAiPlugins",
        "cc-service-app/main/default/genAiFunctions",
    ]),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, required=True)
    args = parser.parse_args()
    destination = ROOT / "test-fixtures/public-agents"
    manifest = {"purpose": "External test inputs; not Ohm submission code", "sources": []}
    for repo, pinned_sha, license_id, includes in SOURCES:
        name = repo.split("/")[-1]
        clone = args.source_root / name
        sha = subprocess.check_output([
            "git", "-C", str(clone), "rev-parse", "--verify", pinned_sha + "^{commit}"
        ], text=True).strip()
        target = destination / name
        entries = []
        for relative in includes:
            # Read immutable git blobs. Publishing may mutate working-tree bundle metadata,
            # and runtime clones may contain org-specific default-agent usernames.
            files = subprocess.check_output([
                "git", "-C", str(clone), "ls-tree", "-rz", "--name-only", sha, "--", relative
            ]).decode().rstrip("\0").split("\0")
            if not files or not files[0]:
                raise FileNotFoundError(f"{repo}@{sha}:{relative}")
            for file in sorted(files):
                rel = Path(file)
                output = target / rel
                output.parent.mkdir(parents=True, exist_ok=True)
                output.write_bytes(subprocess.check_output([
                    "git", "-C", str(clone), "show", f"{sha}:{file}"
                ]))
                entries.append({"path": str(rel), "sha256": hashlib.sha256(output.read_bytes()).hexdigest()})
        project = json.loads((target / "sfdx-project.json").read_text())
        for package in project["packageDirectories"]:
            directory = target / package["path"]
            if not directory.exists():
                directory.mkdir(parents=True)
                (directory / ".gitkeep").write_text("")
        manifest["sources"].append({
            "repository": f"https://github.com/{repo}", "commit": sha,
            "license": license_id, "directory": name,
            "includedPaths": includes, "files": entries,
        })
        print(f"{name}: {sha} — {len(entries)} files")
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "SOURCES.json").write_text(json.dumps(manifest, indent=2) + "\n")


if __name__ == "__main__":
    main()
