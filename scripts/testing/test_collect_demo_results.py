"""Offline evidence checks for the transition from synchronous to queued audits."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("collect_demo_results", Path(__file__).with_name("collect-demo-results.py"))
collector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(collector)
REPORT_ID = "a00000000000001AAA"
PLANNER_ID = "16j000000000001AAA"


class AuditEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name) / "probe.json"

    def probe(self, label="QUEUED"):
        data = {"planner": "Weather_v1", "plannerId": PLANNER_ID, "status": "Queued" if label == "QUEUED" else "Complete"}
        data["queuedReportId" if label == "QUEUED" else "reportId"] = REPORT_ID
        if label == "RESULT":
            data.update({"grade": "Unknown", "score": None, "findings": 0})
        self.path.write_text(json.dumps({"result": {"compiled": True, "success": True,
                                                   "logs": "|DEBUG|OHM_PUBLIC_" + label + " " + json.dumps(data)}}))

    @staticmethod
    def report(status="Complete", planner="Weather_v1"):
        return {"Id": REPORT_ID, "Target_Planner_Id__c": PLANNER_ID, "Target_Planner_Api_Name__c": planner,
                "Run_Status__c": status, "Efficiency_Grade__c": "Unknown", "Efficiency_Score__c": None,
                "Findings_Count__c": 1, "Modeled_Energy_Wh__c": 100, "Coverage_Status__c": "Partial"}

    def test_submission_alone_is_not_completed_evidence(self):
        self.probe()
        with patch.object(collector, "sf_query") as query:
            result = collector.public_audit_evidence(self.path, "unused", skip_live=True)
        query.assert_not_called()
        self.assertFalse(result["complete"])
        self.assertFalse(result["audits"][0]["completionVerified"])
        self.assertNotIn("energyWh", result["audits"][0])

    def test_exact_completed_report_supplies_metrics(self):
        self.probe()
        with patch.object(collector, "sf_query", return_value=[self.report()]) as query:
            result = collector.public_audit_evidence(self.path, "unused")
        self.assertIn(REPORT_ID, query.call_args.args[1])
        self.assertTrue(result["complete"])
        self.assertEqual(100, result["audits"][0]["energyWh"])

    def test_failed_or_pending_run_does_not_supply_completed_metrics(self):
        self.probe()
        for status in ("Failed", "Queued", "Discovering", "Analyzing"):
            with self.subTest(status=status), patch.object(collector, "sf_query", return_value=[self.report(status)]):
                result = collector.public_audit_evidence(self.path, "unused")
                self.assertFalse(result["complete"])
                self.assertEqual(status, result["audits"][0]["status"])
                self.assertNotIn("energyWh", result["audits"][0])

    def test_missing_or_foreign_report_does_not_verify(self):
        self.probe()
        for rows in ([], [self.report(planner="Other_v1")]):
            with self.subTest(rows=bool(rows)), patch.object(collector, "sf_query", return_value=rows):
                result = collector.public_audit_evidence(self.path, "unused")
                self.assertFalse(result["complete"])

    def test_historical_completed_probe_remains_labeled(self):
        self.probe("RESULT")
        with patch.object(collector, "sf_query") as query:
            result = collector.public_audit_evidence(self.path, skip_live=True)
        query.assert_not_called()
        self.assertTrue(result["complete"])
        self.assertEqual("historical-synchronous-log", result["audits"][0]["evidenceMode"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
