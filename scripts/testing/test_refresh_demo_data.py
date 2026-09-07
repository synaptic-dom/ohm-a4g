"""Offline reset safety regression tests. No Salesforce requests are made."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).with_name("refresh-demo-data.py")
SPEC = importlib.util.spec_from_file_location("refresh_demo_data", MODULE)
reset = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(reset)


class ResetSafetyTests(unittest.TestCase):
    def test_read_only_transport_refuses_mutation_before_cli(self):
        with self.assertRaises(reset.ResetError):
            reset.Salesforce("unused").request(reset.BASE + "/composite", "POST", {})

    def test_pagination_including_queryall_query_locator(self):
        client = reset.Salesforce("unused")
        pages = iter([
            {"totalSize": 2, "done": False, "records": [{"Id": "1"}], "nextRecordsUrl": reset.BASE + "/query/locator"},
            {"totalSize": 2, "done": True, "records": [{"Id": "2"}]},
        ])
        client.request = lambda path: next(pages)
        self.assertEqual(["1", "2"], [row["Id"] for row in client.query("ignored", True)])

    def test_incomplete_page_fails(self):
        client = reset.Salesforce("unused")
        client.request = lambda path: {"totalSize": 2, "done": True, "records": [{"Id": "1"}]}
        with self.assertRaises(reset.ResetError):
            client.query("ignored")

    def test_wrong_org_fails_before_other_reads(self):
        client = reset.Salesforce("unused")
        client.query = lambda query: [{"Id": "wrong", "IsSandbox": True, "OrganizationType": "Developer Edition"}]
        with self.assertRaises(reset.ResetError):
            reset.assert_org_and_idle(client)

    def test_active_audit_fails_before_mutation(self):
        client = reset.Salesforce("unused")
        rows = iter([
            [{"Id": reset.ORG_ID, "IsSandbox": True, "OrganizationType": "Developer Edition"}],
            [{"Id": "audit", "Run_Status__c": "Analyzing"}],
        ])
        client.query = lambda query: next(rows)
        with self.assertRaises(reset.ResetError):
            reset.assert_org_and_idle(client)

    def test_atomic_order_and_response_identity_check(self):
        records = {name: [{"Id": ("00T" if name == "Task" else "a00") + str(index).zfill(15)}]
                   for index, name in enumerate(reset.DELETE_ORDER)}
        request = reset.deletion_request({"records": records})
        self.assertTrue(request["allOrNone"])
        self.assertEqual("delete_Task", request["compositeRequest"][0]["referenceId"])
        self.assertEqual("delete_" + reset.REPORT, request["compositeRequest"][-1]["referenceId"])
        replies = []
        for item in request["compositeRequest"]:
            self.assertIn("allOrNone=true", item["url"])
            record_id = reset.parse_qs(reset.urlsplit(item["url"]).query)["ids"][0]
            replies.append({"referenceId": item["referenceId"], "httpStatusCode": 200,
                            "body": [{"id": record_id, "success": True, "errors": []}]})
        reset.verify_delete_response({"compositeResponse": replies}, request)
        replies[0]["body"][0]["id"] = "wrong"
        with self.assertRaises(reset.ResetError):
            reset.verify_delete_response({"compositeResponse": replies}, request)

    def test_private_backup_round_trip_and_mode(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "backup.json"
            value = {"source": "  exact\n\u00a0text  ", "taskOwner": "private"}
            reset.private_write(output, value)
            self.assertEqual(value, json.loads(output.read_text()))
            self.assertEqual(0o600, output.stat().st_mode & 0o777)

    def test_scope_names_require_exact_families(self):
        self.assertIn(reset.family("Ohm_Weather_Demo_v4"), reset.DEMO_FAMILIES)
        self.assertNotIn(reset.family("Ohm_Weather_Demo_clone_v1"), reset.DEMO_FAMILIES)


if __name__ == "__main__":
    unittest.main(verbosity=2)
