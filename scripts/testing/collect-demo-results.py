#!/usr/bin/env python3
"""Collect credential-free test evidence and live demo metadata without source text.

Run from any directory. The default target is the explicitly created scratch lab.
Only application deploy logs matching ohm-demo-deploy-N.json determine application
freshness; publishing the controlled weather fixture is a separate behavior check.
Missing/unfinished artifacts and failed live queries are recorded, never counted as passes.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
from functools import lru_cache
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "docs/testing/results/2026-09-06/fixed-demo/results.json"
REPORT_FIELDS = [
    "Id", "Name", "Target_Planner_Id__c", "Target_Planner_Api_Name__c", "Run_Status__c",
    "Run_Timestamp__c", "CreatedDate", "Efficiency_Grade__c", "Efficiency_Score__c",
    "Coverage_Status__c", "Agents_Discovered__c", "Topics_Discovered__c", "Actions_Discovered__c",
    "Prompt_Templates_Discovered__c", "Findings_Count__c", "Methodology_Version__c",
    "Modeled_Energy_Wh_Low__c", "Modeled_Energy_Wh__c", "Modeled_Energy_Wh_High__c",
    "Modeled_Savings_Wh_Low__c", "Modeled_Savings_Wh__c", "Modeled_Savings_Wh_High__c",
]
FINDING_FIELDS = [
    "Id", "Agent_Audit_Report__c", "Process_Key__c", "Artifact_Key__c", "Issue_Key__c",
    "Artifact_Type__c", "Artifact_Api_Name__c", "Artifact_Label__c", "Artifact_Tooling_Id__c",
    "Signal_Type__c", "Severity__c", "Confidence__c", "Metric_Value__c", "Metric_Unit__c",
    "Finding_Status__c", "Rec_Status__c", "Remediation_Task_Id__c", "Fix_Type__c",
    "Recommended_Target__c", "Annual_Energy_Savings_Wh_Low__c", "Annual_Energy_Savings_Wh__c",
    "Annual_Energy_Savings_Wh_High__c", "CreatedDate",
]
SNAPSHOT_FIELDS = [
    "Id", "Agent_Audit_Report__c", "Process_Key__c", "Artifact_Key__c", "Artifact_Type__c",
    "Artifact_Api_Name__c", "Artifact_Label__c", "Source_Hash__c", "Source_Kind__c",
    "Source_Version__c", "Source_Path__c", "Coverage_Status__c", "Character_Count__c", "CreatedDate",
]
TASK_FIELDS = ["Id", "Subject", "Status", "IsClosed", "OwnerId", "Owner.Name", "ActivityDate", "WhatId", "CreatedDate", "LastModifiedDate"]


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_text(value, limit=500):
    if value is None:
        return None
    text = str(value)
    text = re.sub(r"https?://\S*(?:frontdoor\.jsp|sid=)\S*", "[redacted login URL]", text, flags=re.I)
    text = re.sub(r"(?i)\b(access_token|refresh_token|authorization|client_secret|password)\b\s*[:=]\s*[^\s,;]+", r"\1=[redacted]", text)
    return text if len(text) <= limit else text[:limit] + " [truncated]"


def select(data, fields):
    return {field: data.get(field) for field in fields}


def provenance(path):
    if not path.exists():
        return {"file": path.name, "state": "missing"}
    return {
        "file": path.name, "state": "present", "sha256": sha256(path.read_bytes()),
        "modifiedAt": datetime.fromtimestamp(path.stat().st_mtime, timezone.utc).isoformat(),
    }


def json_result(path):
    document = json.loads(path.read_text())
    return document, document.get("result", document)


@lru_cache(maxsize=None)
def declared_setup_method(class_name, method_name):
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", class_name or "") or not method_name:
        return False
    expression = re.compile(r"@TestSetup\s+(?:(?:private|public|static)\s+)*void\s+" + re.escape(method_name) + r"\s*\(", re.I)
    for folder in [ROOT / "force-app", ROOT / "test-fixtures"]:
        for source in folder.rglob(class_name + ".cls"):
            if expression.search(source.read_text()):
                return True
    return False


def apex_evidence(path, target_org, skip_live):
    output = {"input": provenance(path)}
    if not path.exists():
        return output
    try:
        _, result = json_result(path)
        summary = result.get("summary", {})
        output["summary"] = select(summary, ["outcome", "testsRan", "passing", "failing", "skipped", "testRunId", "testStartTime", "testExecutionTime"])
        output["tests"] = [{
            "id": test.get("Id"), "class": test.get("ApexClass", {}).get("Name"), "method": test.get("MethodName"),
            "outcome": test.get("Outcome"), "runTimeMs": test.get("RunTime"),
            "message": safe_text(test.get("Message")),
        } for test in result.get("tests", [])]
        output["cliDetailedRecordCount"] = len(output["tests"])
        if not skip_live and summary.get("testRunId") and len(output["tests"]) != summary.get("testsRan"):
            try:
                job_id = summary["testRunId"]
                records = sf_query(target_org,
                    "SELECT Id, ApexClass.Name, MethodName, Outcome, RunTime, AsyncApexJobId "
                    f"FROM ApexTestResult WHERE AsyncApexJobId IN ({id_list([job_id])})", tooling=True)
                original_ids = {test["id"] for test in output["tests"]}
                additions = []
                for test in records:
                    if test["Id"] in original_ids:
                        continue
                    additions.append({"id": test["Id"], "class": (test.get("ApexClass") or {}).get("Name"),
                                      "method": test.get("MethodName"), "outcome": test.get("Outcome"),
                                      "runTimeMs": test.get("RunTime"), "message": None})
                output["tests"].extend(additions)
                output["detailReconciliation"] = {"toolingJobId": job_id, "toolingResultCount": len(records),
                    "additionalRecordCount": len(additions),
                    "note": "Tooling ApexTestResult includes setup executions omitted by the CLI detailed test array. No new test run was started."}
            except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
                output["detailReconciliation"] = {"error": safe_text(str(error))}
        for test in output["tests"]:
            test["kind"] = "TestSetup" if declared_setup_method(test["class"], test["method"]) else "TestMethod"
        output["ordinaryTestMethodCount"] = sum(test["kind"] == "TestMethod" for test in output["tests"])
        output["setupExecutionCount"] = sum(test["kind"] == "TestSetup" for test in output["tests"])
        output["complete"] = bool(summary.get("testsRan") is not None and len(output["tests"]) == summary["testsRan"])
    except (ValueError, TypeError, AttributeError) as error:
        output.update(complete=False, error=f"Could not parse completed Apex result: {type(error).__name__}")
    return output


def jest_evidence(path):
    output = {"input": provenance(path), "complete": False}
    if not path.exists():
        return output
    raw = re.sub(r"\x1b\[[0-9;]*m", "", path.read_text())
    for prefix, field in [("Test Suites", "suites"), ("Tests", "tests")]:
        match = re.search(rf"^{prefix}:\s*(.+)$", raw, re.M)
        if match:
            output[field] = {name: int(count) for count, name in re.findall(r"(\d+)\s+(passed|failed|skipped|total)", match.group(1))}
    output["complete"] = all("total" in output.get(key, {}) for key in ("suites", "tests"))
    output["outcome"] = "Passed" if output["complete"] and not output["tests"].get("failed", 0) and not output["suites"].get("failed", 0) else "Incomplete or failed"
    return output


def parser_evidence(path):
    output = {"input": provenance(path), "complete": False}
    if not path.exists():
        return output
    raw = path.read_text()
    count = re.search(r"^Ran (\d+) tests? in ([\d.]+)s$", raw, re.M)
    output["tests"] = [{"name": name, "outcome": outcome} for name, outcome in re.findall(r"^(test_\w+) \([^\n]+\) \.\.\. (ok|FAIL|ERROR|skipped[^\n]*)$", raw, re.M)]
    if count:
        output["testsRan"] = int(count[1])
        output["durationSeconds"] = float(count[2])
        output["complete"] = len(output["tests"]) == output["testsRan"]
    output["outcome"] = "Passed" if output["complete"] and re.search(r"^OK\s*$", raw, re.M) else "Incomplete or failed"
    return output


def deployment_evidence(path):
    output = {"input": provenance(path)}
    try:
        document, result = json_result(path)
        output.update(select(result, ["id", "status", "success", "completedDate", "numberComponentsDeployed", "numberComponentsTotal", "numberComponentErrors", "numberTestErrors"]))
        output["exitStatus"] = document.get("status")
        component_types = {}
        for component in result.get("details", {}).get("componentSuccesses", []):
            component_type = component.get("componentType")
            if component_type:
                component_types[component_type] = component_types.get(component_type, 0) + 1
        output["componentTypes"] = component_types
        output["includesServerOrConfigurationChanges"] = any(kind not in {"LightningComponentBundle", "AuraDefinitionBundle"} for kind in component_types)
    except (ValueError, TypeError, AttributeError):
        output["error"] = "Deployment log is not completed JSON"
    return output


def public_audit_evidence(path, target_org=None, skip_live=False):
    output = {"input": provenance(path), "audits": [], "complete": False}
    if not path.exists():
        return output
    try:
        _, result = json_result(path)
        output["execution"] = select(result, ["compiled", "success"])
        for line in result.get("logs", "").splitlines():
            marker = "|DEBUG|OHM_PUBLIC_"
            if marker not in line:
                continue
            label, encoded = line.split(marker, 1)[1].split(" ", 1)
            data = json.loads(encoded)
            if label in {"RESULT", "QUEUED"}:
                audit = select(data, ["planner", "plannerId", "reportId", "structuralTopics", "structuralActions", "ohmTopics", "ohmActions", "agentGraphPresent", "persistedScopeChars", "coverageStatus", "grade", "score", "energyWh", "findings"])
                audit["detectorCoverage"] = select(data.get("detectorCoverage") or {}, ["INSTRUCTION_BLOAT", "MODEL_RIGHTSIZING", "REDUNDANT_CALLS", "LLM_WHERE_DETERMINISTIC"])
                audit["actionTypes"] = {key: value for key, value in (data.get("actionTypes") or {}).items() if isinstance(value, (int, float)) and re.fullmatch(r"[A-Za-z]+", key)}
                audit["discoveryErrors"] = safe_text(data.get("discoveryErrors"))
                if label == "QUEUED":
                    audit.update({"reportId": data.get("queuedReportId"), "queuedReportId": data.get("queuedReportId"),
                                  "statusAtSubmission": data.get("status"), "asyncJobId": data.get("asyncJobId"),
                                  "evidenceMode": "asynchronous", "completionVerified": False})
                    for key in ["grade", "score", "energyWh", "findings", "coverageStatus", "detectorCoverage"]:
                        audit.pop(key, None)
                    audit["inventoryErrors"] = safe_text(data.get("inventoryErrors"))
                else:
                    # Preserve historical pre-async probe files as labeled evidence.
                    audit.update({"status": data.get("status", "Complete"), "evidenceMode": "historical-synchronous-log",
                                  "completionVerified": bool(data.get("reportId")) and data.get("status", "Complete") == "Complete"})
                output["audits"].append(audit)
            elif label == "FULL":
                output["fullInventory"] = select(data, ["agents", "topics", "actions", "promptTemplates"])
                output["fullInventory"]["findings"] = [select(finding, [
                    "signalType", "artifactType", "artifactApiName", "artifactToolingId", "severity", "confidence",
                    "metricValue", "metricUnit", "reviewRequired", "boundModel", "fixType", "recommendedTarget",
                ]) for finding in data.get("findings", [])]
        queued = [audit for audit in output["audits"] if audit["evidenceMode"] == "asynchronous"]
        if queued and (skip_live or not target_org):
            output["state"] = "Reports submitted; completion not checked because live collection is disabled."
        elif queued:
            report_ids = [audit["reportId"] for audit in queued]
            fields = ["Id", "Target_Planner_Id__c", "Target_Planner_Api_Name__c", "Run_Status__c", "Efficiency_Grade__c",
                      "Efficiency_Score__c", "Findings_Count__c", "Modeled_Energy_Wh__c", "Coverage_Status__c", "Discovery_Errors__c"]
            rows = sf_query(target_org, f"SELECT {', '.join(fields)} FROM Agent_Audit_Report__c WHERE Id IN ({id_list(report_ids)})")
            by_id = {row["Id"]: row for row in rows}
            for audit in queued:
                row = by_id.get(audit["reportId"])
                if row is None:
                    audit["status"] = "Missing"
                    continue
                if row.get("Target_Planner_Id__c") != audit["plannerId"] or row.get("Target_Planner_Api_Name__c") != audit["planner"]:
                    audit["status"] = "Planner identity mismatch"
                    continue
                audit["status"] = row.get("Run_Status__c")
                audit["discoveryErrors"] = safe_text(row.get("Discovery_Errors__c"))
                audit["completionVerified"] = audit["status"] == "Complete"
                if audit["completionVerified"]:
                    audit.update({"grade": row.get("Efficiency_Grade__c"), "score": row.get("Efficiency_Score__c"),
                                  "energyWh": row.get("Modeled_Energy_Wh__c"), "findings": row.get("Findings_Count__c"),
                                  "coverageStatus": row.get("Coverage_Status__c")})
        output["complete"] = bool(output["audits"]) and bool(output["execution"].get("success")) and all(audit["completionVerified"] for audit in output["audits"])
    except (RuntimeError, subprocess.TimeoutExpired) as error:
        output["error"] = safe_text(str(error))
    except (ValueError, TypeError, AttributeError, KeyError):
        output["error"] = "Public audit log is not completed JSON"
    return output


def sf_query(target, query, tooling=False):
    # Argument arrays, never shell execution. These are data queries with explicit field lists;
    # org display/auth commands and unfiltered CLI output are intentionally never collected.
    command = ["sf", "data", "query", "--target-org", target, "--query", query, "--json"]
    if tooling:
        command.append("--use-tooling-api")
    completed = subprocess.run(command, capture_output=True, text=True, timeout=90)
    try:
        document = json.loads(completed.stdout)
    except ValueError as error:
        raise RuntimeError("Salesforce query returned non-JSON output") from error
    if completed.returncode or document.get("status"):
        raise RuntimeError("Salesforce query failed: " + safe_text(document.get("name") or "unspecified error", 100))
    result = document.get("result", {})
    records = result.get("records", [])
    if result.get("done") is False or result.get("totalSize", len(records)) != len(records):
        raise RuntimeError("Salesforce query returned an incomplete record page; evidence collection stopped")
    return records


def id_list(values):
    values = sorted(set(values))
    if not values or any(not re.fullmatch(r"[A-Za-z0-9]{15}(?:[A-Za-z0-9]{3})?", value or "") for value in values):
        raise ValueError("Expected nonempty Salesforce record IDs")
    return ",".join("'" + value + "'" for value in values)


def query_rows(target, object_name, fields, where):
    rows = sf_query(target, f"SELECT {', '.join(fields)} FROM {object_name} WHERE {where} ORDER BY CreatedDate ASC, Id ASC")
    return [{field: row.get(field) for field in fields if "." not in field} for row in rows]


def controlled_metadata(target, task_id):
    result = {"orgAlias": target, "logicalProcess": "ohm_weather_demo", "complete": False}
    reports_raw = sf_query(target,
        f"SELECT {', '.join(REPORT_FIELDS)}, Impact_Snapshot__c FROM Agent_Audit_Report__c "
        "WHERE Target_Type__c = 'Process' AND Target_Planner_Api_Name__c LIKE 'Ohm_Weather_Demo%' ORDER BY CreatedDate ASC, Id ASC")
    reports_raw = [row for row in reports_raw if re.sub(r"_v\d+$", "", (row.get("Target_Planner_Api_Name__c") or "").lower()) == "ohm_weather_demo"]
    reports = []
    for row in reports_raw:
        report = select(row, REPORT_FIELDS)
        if row.get("Impact_Snapshot__c"):
            try:
                impact = json.loads(row["Impact_Snapshot__c"])
                report["modeledScenario"] = select(impact, ["scope", "comparisonKey", "artifactCount", "assumptionSummary"])
            except (ValueError, TypeError):
                report["modeledScenarioError"] = "Invalid stored impact JSON"
        reports.append(report)
    result["reports"] = reports
    result["findings"] = []
    result["snapshots"] = []
    if reports:
        where = f"Agent_Audit_Report__c IN ({id_list([report['Id'] for report in reports])})"
        with ThreadPoolExecutor(max_workers=2) as pool:
            findings = pool.submit(query_rows, target, "Finding__c", FINDING_FIELDS, where)
            snapshots = pool.submit(query_rows, target, "Audit_Artifact_Snapshot__c", SNAPSHOT_FIELDS, where)
            result["findings"] = findings.result()
            result["snapshots"] = snapshots.result()
    task_ids = [task_id] + [finding["Remediation_Task_Id__c"] for finding in result["findings"] if finding.get("Remediation_Task_Id__c")]
    task_where = f"Id IN ({id_list(task_ids)})"
    if reports:
        task_where += f" OR WhatId IN ({id_list([report['Id'] for report in reports])})"
    tasks = sf_query(target, f"SELECT {', '.join(TASK_FIELDS)} FROM Task WHERE {task_where} ORDER BY CreatedDate ASC, Id ASC")
    linked_task_ids = {finding["Remediation_Task_Id__c"] for finding in result["findings"] if finding.get("Remediation_Task_Id__c")}
    result["taskIdsWithoutFindingLinks"] = [task["Id"] for task in tasks if task["Id"] not in linked_task_ids]
    result["tasks"] = [{**select(task, [field for field in TASK_FIELDS if "." not in field]), "ownerName": (task.get("Owner") or {}).get("Name")} for task in tasks]
    task_links = {}
    for finding in result["findings"]:
        if finding.get("Issue_Key__c") and finding.get("Remediation_Task_Id__c"):
            task_links.setdefault(finding["Issue_Key__c"], set()).add(finding["Remediation_Task_Id__c"])
    result["taskIdsByStableIssue"] = {key: sorted(values) for key, values in task_links.items()}
    result["issuesWithMultipleTaskIds"] = [key for key, values in task_links.items() if len(values) > 1]
    result["complete"] = True
    return result


def application_source():
    def git(*args):
        return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True).stdout.strip()
    digest = hashlib.sha256()
    files = sorted(path for path in (ROOT / "force-app").rglob("*") if path.is_file())
    for path in files:
        digest.update(str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() + b"\0")
    return {"gitCommit": git("rev-parse", "HEAD"), "gitBranch": git("branch", "--show-current"),
            "workingTreeDirty": bool(git("status", "--porcelain")), "applicationSourceSha256": digest.hexdigest(), "applicationFileCount": len(files)}


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00")) if value else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-directory", type=Path, default=Path("/tmp"))
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--target-org", default="ohm-audit-lab")
    parser.add_argument("--task-id", default="00TEc00000a9bLNMAY")
    parser.add_argument("--skip-live", action="store_true", help="Collect files only, marking live evidence skipped")
    args = parser.parse_args()
    apex_path = args.input_directory / "ohm-demo-apex-final-2-complete.json"
    if not apex_path.exists() or not apex_path.stat().st_size:
        apex_path = args.input_directory / "ohm-demo-apex-final-2.json"
    jest_paths = sorted(args.input_directory.glob("ohm-demo-jest-final-*.txt"), key=lambda path: int(re.search(r"-(\d+)\.txt$", path.name)[1]), reverse=True)
    jest = next((candidate for path in jest_paths if (candidate := jest_evidence(path)).get("complete")), jest_evidence(args.input_directory / "ohm-demo-jest-final-2.txt"))
    evidence = {
        "schemaVersion": 1, "collectedAt": datetime.now(timezone.utc).isoformat(), "applicationSource": application_source(),
        "scope": "Tests, application deployment metadata, public audit measurements, and controlled weather remediation metadata. Modeled energy is not runtime telemetry.",
        "privacy": "Explicit field allowlists. No credentials, auth output, raw source, source JSON, graph JSON, Task descriptions or raw debug logs are retained.",
        "apex": apex_evidence(apex_path, args.target_org, args.skip_live),
        "jest": jest,
        "sourceParser": parser_evidence(args.input_directory / "ohm-demo-parser-final.txt"),
        "publicAudits": public_audit_evidence(args.input_directory / "ohm-demo-public-audits.json", args.target_org, args.skip_live),
    }
    deployment_paths = sorted(args.input_directory.glob("ohm-demo-deploy-*.json"), key=lambda path: int(re.search(r"-(\d+)\.json$", path.name)[1]))
    evidence["applicationDeployments"] = [deployment_evidence(path) for path in deployment_paths]
    latest = evidence["applicationDeployments"][-1] if deployment_paths else {}
    latest_server = next((deployment for deployment in reversed(evidence["applicationDeployments"])
                          if deployment.get("success") and deployment.get("includesServerOrConfigurationChanges")), {})
    started = parse_time(evidence["apex"].get("summary", {}).get("testStartTime"))
    deployed = parse_time(latest_server.get("completedDate"))
    latest_ui = next((deployment for deployment in reversed(evidence["applicationDeployments"])
                      if deployment.get("success") and any(kind in deployment.get("componentTypes", {}) for kind in ["LightningComponentBundle", "AuraDefinitionBundle"])), {})
    ui_deployed = parse_time(latest_ui.get("completedDate"))
    jest_completed = parse_time(evidence["jest"].get("input", {}).get("modifiedAt"))
    evidence["validationFreshness"] = {
        "latestApplicationDeploymentId": latest.get("id"), "latestApplicationDeploymentSucceeded": latest.get("success"),
        "latestServerDeploymentId": latest_server.get("id"),
        "apexRunStartedAfterLatestServerDeployment": started >= deployed if started and deployed else None,
        "latestUiDeploymentId": latest_ui.get("id"),
        "jestResultWrittenAfterLatestUiDeployment": jest_completed >= ui_deployed if jest_completed and ui_deployed else None,
        "note": "Numbered application deployments are classified by component types. LWC-only changes do not invalidate the Apex gate. Controlled agent publication is separate behavior evidence. Jest file time records result completion, not test start.",
    }
    if args.skip_live:
        evidence["controlledDemo"] = {"complete": False, "state": "skipped by caller"}
    else:
        try:
            evidence["controlledDemo"] = controlled_metadata(args.target_org, args.task_id)
        except (RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
            evidence["controlledDemo"] = {"complete": False, "error": safe_text(str(error))}
    evidence["collectionComplete"] = all([
        evidence["apex"].get("complete"), evidence["jest"].get("complete"), evidence["sourceParser"].get("complete"),
        evidence["publicAudits"].get("complete"), evidence["controlledDemo"].get("complete"),
    ])
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n")
    print(args.output)
    print(json.dumps({"collectionComplete": evidence["collectionComplete"], "apex": evidence["apex"].get("summary"),
                      "jest": evidence["jest"].get("tests"), "parser": evidence["sourceParser"].get("testsRan"),
                      "controlledReports": len(evidence["controlledDemo"].get("reports", [])),
                      "controlledTasks": len(evidence["controlledDemo"].get("tasks", [])),
                      "liveError": evidence["controlledDemo"].get("error")}, sort_keys=True))
    return 0 if evidence["collectionComplete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
