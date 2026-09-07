#!/usr/bin/env python3
"""Back up and optionally soft-delete the four OHM scratch-demo audit histories.

Dry run (default) makes a complete private JSON backup and prints only scope/counts:
    python3 scripts/testing/refresh-demo-data.py
Apply the exact reviewed data state (makes another backup and rechecks before DML):
    python3 scripts/testing/refresh-demo-data.py --apply --expect-plan-sha <dry-run SHA>

This deliberately supports only the pinned scratch org and named demo families.
It never deletes agent/Flow metadata, runs Apex, purges the Recycle Bin, or reads
CLI auth files. Authentication stays inside `sf api request rest`. Deletion uses
one Composite request with allOrNone=true, at most five ordered collections of
200 records each. Both the outer request and every collection roll back on error.
Backups include all fields exposed by describe, not truncated SOQL FIELDS(ALL)
results. Every query follows and verifies pagination, including archived Tasks.
Source text, record bodies, and raw CLI error output are never printed.

References:
https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_composite_composite_post.htm
https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/resources_composite_sobjects_collections_delete.htm
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import parse_qs, urlencode, urlsplit

ORG_ID = "00DEc00000kvSbNMAU"
DEFAULT_ALIAS = "ohm-audit-lab"
BASE = "/services/data/v67.0"
ROOT = Path(__file__).resolve().parents[2]
DEMO_FAMILIES = {"ActionDefinitions", "ActionChaining", "PromptTemplateActions", "Ohm_Weather_Demo"}
REPORT = "Agent_Audit_Report__c"
FINDING = "Finding__c"
SNAPSHOT = "Audit_Artifact_Snapshot__c"
SOURCE = "Ohm_Instruction_Source__c"
DELETE_ORDER = ("Task", FINDING, SNAPSHOT, SOURCE, REPORT)
ACTIVE_REPORTS = {"Queued", "Discovering", "Retrieving", "Analyzing", "Finalizing", "Running", "Processing"}
ACTIVE_JOBS = "'Holding','Queued','Preparing','Processing'"
ID = re.compile(r"[A-Za-z0-9]{15}(?:[A-Za-z0-9]{3})?\Z")
API_NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*\Z")


class ResetError(RuntimeError):
    """Messages contain only operator-safe metadata, never record/source bodies."""


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def id_list(values):
    values = sorted(set(values))
    if not values or any(not ID.fullmatch(value or "") for value in values):
        raise ResetError("Invalid or empty record identity list; no deletion attempted.")
    return ",".join("'" + value + "'" for value in values)


def family(api_name):
    return re.sub(r"_v[1-9][0-9]*$", "", api_name or "")


def rows_by_id(rows):
    return {row["Id"]: row for row in rows}


class Salesforce:
    def __init__(self, alias, allow_mutation=False):
        self.alias = alias
        self.allow_mutation = allow_mutation
        self.schemas = {}

    def request(self, path, method="GET", body=None):
        if not path.startswith(BASE + "/") or "\n" in path:
            raise ResetError("Refused an unexpected API endpoint.")
        if method != "GET" and not (self.allow_mutation and method == "POST" and path == BASE + "/composite"):
            raise ResetError("Mutations are disabled or outside the reset operation.")
        command = ["sf", "api", "request", "rest", path, "--target-org", self.alias,
                   "--method", method, "--header", "Accept: application/json"]
        encoded = None
        if body is not None:
            command += ["--header", "Content-Type: application/json", "--body", "-"]
            encoded = json.dumps(body, separators=(",", ":"))
        try:
            result = subprocess.run(command, input=encoded, text=True, capture_output=True, timeout=120, check=False)
        except subprocess.TimeoutExpired as error:
            raise ResetError("Salesforce request timed out. If apply was submitted, inspect the private journal before retrying.") from error
        try:
            document = json.loads(result.stdout)
        except ValueError as error:
            raise ResetError("Salesforce returned non-JSON output; raw output was withheld.") from error
        if result.returncode or (isinstance(document, list) and document and "errorCode" in document[0]):
            raise ResetError("Salesforce request failed; no raw response or credentials were printed.")
        return document

    def query(self, soql, include_archived=False):
        resource = "queryAll" if include_archived else "query"
        path = BASE + "/" + resource + "?" + urlencode({"q": soql})
        records, seen_pages = [], set()
        expected_total = None
        while path:
            if path in seen_pages or len(seen_pages) >= 10000:
                raise ResetError("Query pagination repeated or exceeded its limit.")
            seen_pages.add(path)
            page = self.request(path)
            if not isinstance(page, dict) or not isinstance(page.get("records"), list) or not isinstance(page.get("done"), bool):
                raise ResetError("Invalid query page; complete export could not be proven.")
            if expected_total is None:
                expected_total = page.get("totalSize")
            elif page.get("totalSize") != expected_total:
                raise ResetError("Record count changed during pagination.")
            records.extend(page["records"])
            if page["done"]:
                path = None
            else:
                path = page.get("nextRecordsUrl")
                if not isinstance(path, str) or not (path.startswith(BASE + "/query/") or path.startswith(BASE + "/queryAll/")):
                    raise ResetError("Incomplete query has no valid continuation URL.")
        if expected_total != len(records) or len({row["Id"] for row in records}) != len(records):
            raise ResetError("Export count or record identities did not match the complete query.")
        return records

    def describe(self, object_name):
        if object_name not in self.schemas:
            document = self.request(BASE + "/sobjects/" + object_name + "/describe")
            if not document.get("queryable") or not document.get("fields"):
                raise ResetError("Object cannot be fully exported: " + object_name)
            self.schemas[object_name] = document
        return self.schemas[object_name]

    def full_rows(self, object_name, where):
        schema = self.describe(object_name)
        fields = sorted(field["name"] for field in schema["fields"])
        if "Id" not in fields or any(not API_NAME.fullmatch(name) for name in fields):
            raise ResetError("Unexpected describe field identity for " + object_name)
        # Explicit fields avoid FIELDS(ALL)'s 200-row restriction and truncation risks.
        rows = self.query("SELECT " + ",".join(fields) + " FROM " + object_name
                          + " WHERE IsDeleted = false AND (" + where + ") ORDER BY Id", include_archived=True)
        for row in rows:
            if set(row) - {"attributes"} != set(fields):
                raise ResetError("Full-field export is incomplete for " + object_name)
        return rows


def assert_org_and_idle(sf):
    org = sf.query("SELECT Id,IsSandbox,OrganizationType FROM Organization")
    if len(org) != 1 or org[0]["Id"] != ORG_ID or org[0]["IsSandbox"] is not True or org[0]["OrganizationType"] != "Developer Edition":
        raise ResetError("Reset is restricted to scratch org " + ORG_ID + " with IsSandbox=true and Developer Edition.")
    reports = sf.query("SELECT Id,Run_Status__c FROM " + REPORT)
    if any(row.get("Run_Status__c") in ACTIVE_REPORTS for row in reports):
        raise ResetError("An OHM audit report is active; wait for completion before refreshing data.")
    jobs = sf.query("SELECT Id,Status,ApexClass.Name FROM AsyncApexJob WHERE Status IN (" + ACTIVE_JOBS + ") AND ApexClass.Name LIKE 'Ohm%'")
    if jobs:
        raise ResetError("An OHM asynchronous job is active; no data may be refreshed yet.")
    return {key: org[0][key] for key in ("Id", "IsSandbox", "OrganizationType")}


def collect(sf):
    org = assert_org_and_idle(sf)
    planners = sf.query("SELECT Id,DeveloperName FROM GenAiPlannerDefinition")
    selected_planners = {row["Id"]: row["DeveloperName"] for row in planners if family(row["DeveloperName"]) in DEMO_FAMILIES}
    if not selected_planners:
        raise ResetError("No known demo planners exist in this scratch org.")
    index = sf.query("SELECT Id,Target_Type__c,Target_Planner_Id__c,Target_Planner_Api_Name__c FROM " + REPORT)
    report_ids = []
    for row in index:
        if row.get("Target_Type__c") != "Process" or family(row.get("Target_Planner_Api_Name__c")) not in DEMO_FAMILIES:
            continue
        if selected_planners.get(row.get("Target_Planner_Id__c")) != row.get("Target_Planner_Api_Name__c"):
            raise ResetError("A demo report's planner ID and API name cannot be verified: " + row["Id"])
        report_ids.append(row["Id"])
    exports = {name: [] for name in DELETE_ORDER}
    if report_ids:
        report_where = "Id IN (" + id_list(report_ids) + ")"
        exports[REPORT] = sf.full_rows(REPORT, report_where)
        for object_name in (FINDING, SNAPSHOT):
            exports[object_name] = sf.full_rows(object_name, "Agent_Audit_Report__c IN (" + id_list(report_ids) + ")")
    exports[SOURCE] = sf.full_rows(SOURCE, "Planner_Id__c IN (" + id_list(selected_planners) + ")")
    findings = rows_by_id(exports[FINDING])
    task_ids = {row["Remediation_Task_Id__c"] for row in findings.values() if row.get("Remediation_Task_Id__c")}
    if any(not value.startswith("00T") or not ID.fullmatch(value) for value in task_ids):
        raise ResetError("A remediation link is not a valid Task identity.")
    related_tasks = []
    if report_ids:
        related_tasks = sf.query("SELECT Id,WhatId FROM Task WHERE IsDeleted = false AND WhatId IN (" + id_list(report_ids) + ")", include_archived=True)
        if any(row["Id"] not in task_ids for row in related_tasks):
            raise ResetError("A selected report has a Task without a scoped finding link; parent deletion is unsafe.")
        events = sf.query("SELECT Id FROM Event WHERE IsDeleted = false AND WhatId IN (" + id_list(report_ids) + ")", include_archived=True)
        if events:
            raise ResetError("A selected report has an unrelated Event; parent deletion is unsafe.")
    if task_ids:
        exports["Task"] = sf.full_rows("Task", "Id IN (" + id_list(task_ids) + ")")
        external_links = sf.query("SELECT Id,Agent_Audit_Report__c FROM " + FINDING
                                  + " WHERE Remediation_Task_Id__c IN (" + id_list(task_ids) + ")")
        if any(row["Id"] not in findings for row in external_links):
            raise ResetError("A remediation Task is shared with a finding outside the reset scope.")
        for task in exports["Task"]:
            if not task.get("Subject", "").startswith("Ohm:") or task.get("WhatId") not in report_ids:
                raise ResetError("A finding-linked Task is not tied to a selected OHM report: " + task["Id"])
    # A report can have direct activities; findings can also acquire them if their
    # org configuration changes. Never let parent deletion silently sweep them up.
    if findings:
        for activity in ("Task", "Event"):
            attached = sf.query("SELECT Id FROM " + activity + " WHERE IsDeleted = false AND WhatId IN ("
                                + id_list(findings) + ")", include_archived=True)
            if attached:
                raise ResetError("A selected finding has an unexpected activity; reset stopped.")
    for object_name, rows in exports.items():
        if len(rows) > 200:
            raise ResetError("More than 200 " + object_name + " rows need a separately reviewed reset; nothing deleted.")
        sf.describe(object_name)
    scope = {
        "org": org, "families": sorted(DEMO_FAMILIES), "planners": selected_planners,
        "reportsPreservedOutsideScope": len(index) - len(report_ids),
        "counts": {name: len(exports[name]) for name in DELETE_ORDER},
        "records": exports,
    }
    # Include source field values, Task owner/due dates, and report job state in
    # the reviewed identity, so changes after dry run require another review.
    scope["planSha256"] = digest(scope)
    return scope


def private_write(path, value):
    data = (json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n").encode()
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "wb") as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())
    if json.loads(path.read_text()) != value:
        raise ResetError("Private backup read-back verification failed.")
    return hashlib.sha256(data).hexdigest()


def backup(scope, schemas, root):
    root = root.expanduser().resolve()
    if root == ROOT or ROOT in root.parents:
        raise ResetError("Full record backups must be outside this Git workspace.")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.stat().st_mode & 0o077:
        raise ResetError("Backup root must be private (chmod 700); no backup or deletion performed.")
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-")
    folder = Path(tempfile.mkdtemp(prefix=stamp, dir=root))
    hashes = {}
    for object_name, rows in scope["records"].items():
        hashes[object_name + ".json"] = private_write(folder / (object_name + ".json"), rows)
        hashes[object_name + ".schema.json"] = private_write(folder / (object_name + ".schema.json"), schemas[object_name])
    manifest = {key: value for key, value in scope.items() if key != "records"}
    manifest.update({"createdAt": datetime.now(timezone.utc).isoformat(), "filesSha256": hashes,
                     "recordIds": {name: [row["Id"] for row in rows] for name, rows in scope["records"].items()},
                     "deleteMode": "Soft delete; Recycle Bin is never purged", "deleteOrder": list(DELETE_ORDER)})
    private_write(folder / "manifest.json", manifest)
    return folder


def deletion_request(scope):
    requests = []
    for object_name in DELETE_ORDER:
        ids = [row["Id"] for row in scope["records"][object_name]]
        if not ids:
            continue
        requests.append({"method": "DELETE", "referenceId": "delete_" + object_name,
                         "url": BASE + "/composite/sobjects?" + urlencode({"ids": ",".join(ids), "allOrNone": "true"})})
    return {"allOrNone": True, "compositeRequest": requests}


def verify_delete_response(response, request):
    replies = response.get("compositeResponse", []) if isinstance(response, dict) else []
    if len(replies) != len(request["compositeRequest"]):
        raise ResetError("Delete response is incomplete; inspect the private journal before retrying.")
    for sent, reply in zip(request["compositeRequest"], replies):
        if reply.get("referenceId") != sent["referenceId"] or reply.get("httpStatusCode") != 200:
            raise ResetError("Composite reset failed and requested rollback; inspect its private response.")
        results = reply.get("body")
        if not isinstance(results, list) or not results or any(row.get("success") is not True or row.get("errors") for row in results):
            raise ResetError("A delete operation failed and requested rollback; inspect its private response.")
        sent_ids = set(parse_qs(urlsplit(sent["url"]).query)["ids"][0].split(","))
        if len(results) != len(sent_ids) or {row.get("id") for row in results} != sent_ids:
            raise ResetError("Delete response identities are incomplete; inspect the private journal before retrying.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--target-org", default=DEFAULT_ALIAS, help="CLI alias; the resulting org must still match the pinned scratch org")
    parser.add_argument("--apply", action="store_true", help="Soft-delete only the reviewed scope after a new verified backup")
    parser.add_argument("--expect-plan-sha", help="Required with --apply: SHA printed by the reviewed dry run")
    parser.add_argument("--backup-root", type=Path, default=Path.home() / ".local/state/ohm/demo-refresh" / ORG_ID)
    args = parser.parse_args()
    os.umask(0o077)
    if args.apply and not re.fullmatch(r"[0-9a-f]{64}", args.expect_plan_sha or ""):
        parser.error("--apply requires --expect-plan-sha from a reviewed dry run")
    sf = Salesforce(args.target_org, allow_mutation=args.apply)
    scope = collect(sf)
    if args.apply and scope["planSha256"] != args.expect_plan_sha:
        raise ResetError("Data changed since the reviewed dry run. Run another dry run; nothing deleted.")
    folder = backup(scope, sf.schemas, args.backup_root)
    summary = {key: value for key, value in scope.items() if key not in {"records", "planners"}}
    summary.update({"mode": "dry-run", "backupDirectory": str(folder), "backupVerified": True})
    if args.apply:
        current = collect(sf)
        if current["planSha256"] != scope["planSha256"]:
            raise ResetError("Data changed during backup; nothing deleted. Backup: " + str(folder))
        assert_org_and_idle(sf)
        request = deletion_request(scope)
        private_write(folder / "delete-request.json", request)
        if request["compositeRequest"]:
            # Persist intent before dispatch. A timeout is an uncertain result;
            # never retry the mutation automatically.
            private_write(folder / "apply-started.json", {"startedAt": datetime.now(timezone.utc).isoformat(), "planSha256": scope["planSha256"]})
            response = sf.request(BASE + "/composite", "POST", request)
            private_write(folder / "delete-response.json", response)
            verify_delete_response(response, request)
        remaining = {}
        for object_name, rows in scope["records"].items():
            remaining[object_name] = 0 if not rows else len(sf.query("SELECT Id FROM " + object_name + " WHERE IsDeleted = false AND Id IN (" + id_list(row["Id"] for row in rows) + ")", include_archived=True))
        private_write(folder / "verification.json", {"remainingLiveRecords": remaining})
        if any(remaining.values()):
            raise ResetError("Some scoped records remain live; inspect the private verification before retrying.")
        summary.update({"mode": "applied", "remainingLiveRecords": remaining})
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (ResetError, OSError) as error:
        print("Demo reset stopped: " + str(error), file=sys.stderr)
        sys.exit(1)
