#!/usr/bin/env python3
"""Collect allowlisted, credential-free evidence from completed scratch-lab CLI runs."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-directory", type=Path, default=Path("/tmp"))
    args = parser.parse_args()
    evidence = {
        "date": "2026-09-06", "applicationCommit": "038b5a0",
        "orgAlias": "ohm-audit-lab", "orgId": "00DEc00000kvSbNMAU",
        "expires": "2026-09-13", "execution": "Live Salesforce scratch org, API 67.0",
        "testRuns": {}, "publicAudits": [], "deployments": {},
    }
    for label in ["acceptance-results", "baseline-results", "upstream-results", "upstream-permissions-retest"]:
        path = args.input_directory / f"ohm-audit-lab-{label}.json"
        if not path.exists():
            continue
        document = json.loads(path.read_text())
        result = document.get("result") or document
        summary = result.get("summary", {})
        evidence["testRuns"][label] = {
            "summary": {key: summary.get(key) for key in [
                "outcome", "testsRan", "passing", "failing", "skipped", "testRunId", "testStartTime"
            ]},
            "tests": [{
                "class": test.get("ApexClass", {}).get("Name"),
                "method": test.get("MethodName"), "outcome": test.get("Outcome"),
                "message": test.get("Message"),
            } for test in result.get("tests", [])],
        }
    document = json.loads((args.input_directory / "ohm-audit-lab-public-audit.json").read_text())
    result = document.get("result", {})
    evidence["auditExecution"] = {key: result.get(key) for key in ["compiled", "success", "compileProblem", "exceptionMessage"]}
    for line in result.get("logs", "").splitlines():
        for prefix, field in [("OHM_PUBLIC_RESULT ", "publicAudits"), ("OHM_PUBLIC_FULL ", "fullDiscovery")]:
            marker = "|DEBUG|" + prefix
            if marker in line:
                data = json.loads(line.split(marker, 1)[1])
                if field == "publicAudits":
                    evidence[field].append(data)
                else:
                    evidence[field] = data
    model_path = args.input_directory / "ohm-audit-lab-model-connectivity.json"
    if model_path.exists():
        model_result = json.loads(model_path.read_text()).get("result", {})
        evidence["modelConnectivity"] = {
            "compiled": model_result.get("compiled"), "success": model_result.get("success"),
            "scope": "One direct Models API request; not an end-to-end Ask Ohm or agent behavior test",
        }
        marker = "|DEBUG|OHM_LAB_MODEL "
        for line in model_result.get("logs", "").splitlines():
            if marker in line:
                evidence["modelConnectivity"]["result"] = json.loads(line.split(marker, 1)[1])
    for label in ["ohm-deploy", "recipes-deploy", "localinfo-deploy", "controls-deploy",
                  "acceptance-deploy", "fixture-permissions-deploy",
                  "publish-ActionDefinitions", "publish-ActionChaining", "publish-PromptTemplateActions",
                  "publish-Local_Info_Agent", "publish-Local_Info_Agent-retry"]:
        document = json.loads((args.input_directory / f"ohm-audit-lab-{label}.json").read_text())
        result = document.get("result") or {}
        evidence["deployments"][label] = {
            "exitStatus": document.get("status"), "message": document.get("message"),
            **{key: result.get(key) for key in ["id", "status", "success", "botDeveloperName", "numberComponentsDeployed"]},
        }
    output = ROOT / "docs/testing/results/2026-09-06/lab-results.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2) + "\n")
    print(output)
    for name, run in evidence["testRuns"].items():
        print(name, run["summary"])


if __name__ == "__main__":
    main()
