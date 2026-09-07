"""Offline safety regressions; these tests never launch sf or contact Salesforce."""
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

SPEC = importlib.util.spec_from_file_location("setup_connection", Path(__file__).with_name("setup-connection.py"))
setup = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(setup)

USER = "005000000000001AAA"
PERM = "0PS000000000001AAA"
ASSIGNMENT = "0Pa000000000001AAA"
APP_ID = "0xI000000000001AAA"
CONSUMER = "888000000000001AAA"


class FakeSalesforce:
    def __init__(self, directory, original="false", exists=False):
        self.directory = Path(directory)
        self.target_org = "test-org"
        self.steps = []
        self.settings = {setup.SETTING: original, "enablePackageEcaOauthFromDevOrg": "false"}
        self.present = exists
        self.assignment = False
        self.permission = False
        self.uncertain_assignment = False
        self.events = []

    def command(self, args, label):
        return {"instanceUrl": "https://example.my.salesforce.com", "username": "admin@example.com",
                "accessToken": "never-print-this-test-token"}

    def query(self, query):
        if "FROM User " in query:
            return [{"Id": USER, "Username": "admin@example.com", "Email": "admin@example.com", "IsActive": True}]
        if "FROM PermissionSetAssignment " in query:
            return [{"Id": ASSIGNMENT}] if self.assignment else []
        if "FROM PermissionSet " in query:
            return [{"Id": PERM}] if self.permission else []
        raise AssertionError(query)

    def exists(self, *_):
        return self.present

    def delete_record(self, sobject, record_id):
        self.rest("sobjects/" + sobject + "/" + record_id, "DELETE")

    def deploy(self, directory, label):
        self.events.append(label)
        self.steps.append({"step": label})
        for path in Path(directory).rglob("*.xml"):
            root = ET.parse(path).getroot()
            if root.tag.endswith("}ExternalClientAppSettings"):
                self.settings[setup.SETTING] = setup.xml_text(root, setup.SETTING)
            if "temporary-permission" in str(path):
                self.permission = True

    def retrieve(self, kind, name, label):
        directory = self.directory / ("retrieved-" + str(len(self.events)))
        self.events.append(label)
        setup.write_xml(directory, "ExternalClientApp.settings", "ExternalClientAppSettings",
                        "".join(setup.tag(k, v) for k, v in self.settings.items()))
        return directory

    def rest(self, path, method="GET", body=None):
        self.events.append((method, path))
        if path == "sobjects/PermissionSetAssignment" and method == "POST":
            self.assignment = True
            if self.uncertain_assignment:
                raise setup.SetupError("Simulated interrupted assignment response.")
            return {"id": ASSIGNMENT}
        if method == "DELETE" and path == "sobjects/PermissionSetAssignment/" + ASSIGNMENT:
            self.assignment = False
            return None
        if method == "DELETE" and path == "sobjects/PermissionSet/" + PERM:
            self.permission = False
            return None
        raise AssertionError((path, method))


class SetupSafetyTests(unittest.TestCase):
    def args(self, update=False):
        return SimpleNamespace(run_as="reader@example.com", audit_user=[], contact_email=None, update=update)

    def credential(self, status="Configured", parameters=None):
        return {"authenticationStatus": status, "authenticationProtocol": "Custom", "externalCredential": setup.EXTERNAL,
                "principalName": setup.PRINCIPAL, "principalType": "NamedPrincipal", "credentials": parameters or {}}

    def test_http_error_cannot_echo_credentials(self):
        response = 'HTTP/1.1 400\ncontent-type: application/json\n[{"errorCode":"INVALID_INPUT","message":"secret-do-not-print"}]'
        with self.assertRaises(setup.ApiError) as caught:
            setup.parse_rest_output(response)
        self.assertEqual(400, caught.exception.status)
        self.assertNotIn("secret-do-not-print", str(caught.exception))

    def test_rest_body_goes_through_stdin_with_logging_disabled(self):
        with tempfile.TemporaryDirectory() as directory:
            sf = setup.Salesforce("explicit-target", directory)
            with patch.object(setup.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "HTTP/1.1 204\n", "")) as run:
                sf.rest("named-credentials/credential", "POST", {"secret": "stdin-only"})
            kwargs = run.call_args.kwargs
            self.assertNotIn("stdin-only", " ".join(run.call_args.args[0]))
            self.assertIn("stdin-only", kwargs["input"])
            self.assertTrue(kwargs["capture_output"])
            self.assertEqual("true", kwargs["env"]["SF_DISABLE_LOG_FILE"])
            self.assertIn("--target-org", run.call_args.args[0])

    def test_cleanup_uses_dedicated_delete_command_and_empty_204_is_valid(self):
        self.assertIsNone(setup.parse_rest_output("HTTP/1.1 204\ncontent-length: 0\n"))
        with tempfile.TemporaryDirectory() as directory:
            sf = setup.Salesforce("explicit-target", directory)
            with patch.object(sf, "command", return_value={"success": True}) as command:
                sf.delete_record("PermissionSet", PERM)
            self.assertEqual(["data", "delete", "record", "--sobject", "PermissionSet", "--record-id", PERM],
                             command.call_args.args[0])

    def test_local_cli_deploy_failure_uses_exact_readonly_job_confirmation(self):
        job = "0Af000000000001AAA"
        failed_cli = {"status": 1, "name": "SourceTrackingError", "data": {"id": job},
                      "message": "arbitrary-secret-do-not-print"}
        with tempfile.TemporaryDirectory() as directory:
            sf = setup.Salesforce("explicit-target", directory)
            with patch.object(sf, "invoke", return_value=subprocess.CompletedProcess([], 1, json.dumps(failed_cli), "")), \
                    patch.object(sf, "command", return_value={"id": job, "status": "Succeeded", "success": True}) as report:
                sf.deploy(Path(directory) / "source", "Create temporary setup permission")
            self.assertEqual(["project", "deploy", "report", "--job-id", job], report.call_args.args[0])
            self.assertEqual(job, sf.steps[0]["deploymentId"])

    def test_failed_owned_permission_deploy_reports_only_allowed_details(self):
        failure = {"status": 1, "message": "arbitrary-secret-do-not-print", "result": {
            "id": "0Af000000000001AAA", "status": "Failed", "success": False, "details": {"componentFailures": [
                {"componentType": "PermissionSet", "fullName": "Ohm_Source_Setup_1234abcd", "problem": "Unknown user permission ExamplePermission"},
                {"componentType": "NamedCredential", "fullName": "SomeOtherComponent", "problem": "other-secret-do-not-print"}]}}}
        with tempfile.TemporaryDirectory() as directory:
            sf = setup.Salesforce("explicit-target", directory)
            with patch.object(sf, "invoke", return_value=subprocess.CompletedProcess([], 1, json.dumps(failure), "")), \
                    self.assertRaises(setup.SetupError) as caught:
                sf.deploy(Path(directory) / "source", "Create temporary setup permission")
            self.assertIn("0Af000000000001AAA", str(caught.exception))
            self.assertIn("Unknown user permission ExamplePermission", str(caught.exception))
            self.assertNotIn("do-not-print", str(caught.exception))

    def test_remote_and_parent_routes_are_rejected(self):
        for path in ["https://other.example/secrets", "//other.example/secrets", "apps/../outside", "/services/data/v67.0/apps#other"]:
            with self.subTest(path=path), self.assertRaises(setup.SetupError):
                setup.api_path(path)

    def test_credential_values_are_encoded_before_body_merge(self):
        payload = setup.vault_payload("key+&=", "space + & secret")
        self.assertEqual({"value": "key%2B%26%3D", "encrypted": True}, payload["credentials"]["ClientIdEncoded"])
        self.assertEqual("space+%2B+%26+secret", payload["credentials"]["ClientSecretEncoded"]["value"])

    def test_current_consumer_accepts_15_18_id_forms_but_not_another_app(self):
        sf = SimpleNamespace(rest=None)
        responses = [{"apps": [{"developerName": setup.APP, "identifier": APP_ID[:15]}]},
                     {"consumers": [{"id": CONSUMER, "url": setup.PREFIX + "apps/oauth/credentials/" + APP_ID + "/" + CONSUMER}]},
                     {"id": CONSUMER, "key": "test-key"}, {"id": CONSUMER[:15], "secret": "test-secret"}]
        with patch.object(sf, "rest", side_effect=responses):
            self.assertEqual(("test-key", "test-secret"), setup.current_credentials(sf))
        responses[1]["consumers"][0]["url"] = setup.PREFIX + "apps/oauth/credentials/0xI000000000009AAA/" + CONSUMER
        with patch.object(sf, "rest", side_effect=responses), self.assertRaises(setup.SetupError):
            setup.current_credentials(sf)

    def test_update_put_requires_get_confirmation(self):
        sf = SimpleNamespace(rest=None)
        with patch.object(sf, "rest", side_effect=[self.credential(), {}]) as rest:
            setup.store_credentials(sf, "test-key", "test-secret", True)
            self.assertEqual("PUT", rest.call_args_list[-1].args[1])
        with patch.object(sf, "rest", side_effect=[setup.ApiError(403, "INSUFFICIENT_ACCESS")]) as rest:
            with self.assertRaises(setup.ApiError):
                setup.store_credentials(sf, "test-key", "test-secret", True)
            self.assertEqual(1, rest.call_count)

    def test_custom_unknown_status_uses_parameter_names_to_detect_existing_vault(self):
        sf = SimpleNamespace(rest=None)
        response = self.credential("Unknown", {"ClientIdEncoded": {}, "ClientSecretEncoded": {}})
        with patch.object(sf, "rest", side_effect=[response, {}]) as rest:
            setup.store_credentials(sf, "test-key", "test-secret", True)
            self.assertEqual("PUT", rest.call_args_list[-1].args[1])
        response["credentials"]["AnotherApplicationParameter"] = {}
        with patch.object(sf, "rest", return_value=response) as rest, self.assertRaises(setup.SetupError):
            setup.store_credentials(sf, "test-key", "test-secret", True)
        self.assertEqual(1, rest.call_count)

    def test_new_vault_post_requires_absent_credential(self):
        sf = SimpleNamespace(rest=None)
        with patch.object(sf, "rest", side_effect=[setup.ApiError(404, "NOT_FOUND"), {}]) as rest:
            setup.store_credentials(sf, "test-key", "test-secret", False)
            self.assertEqual("POST", rest.call_args_list[-1].args[1])
        with patch.object(sf, "rest", return_value=self.credential()) as rest:
            with self.assertRaises(setup.SetupError):
                setup.store_credentials(sf, "test-key", "test-secret", False)
            self.assertEqual(1, rest.call_count)

    def test_new_metadata_never_supplies_or_rotates_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            sf = FakeSalesforce(directory)
            setup.create_application(sf, "reader@example.com", "ops@example.com")
            roots = [ET.parse(p).getroot() for p in Path(directory).rglob("*.xml")]
            self.assertFalse(any(e.tag.rsplit("}", 1)[-1] in {"consumerKey", "consumerSecret"} for r in roots for e in r.iter()))
            rotations = [e.text for r in roots for e in r.iter() if "shouldRotate" in e.tag]
            self.assertEqual(["false", "false"], rotations)
            self.assertTrue(all(p.is_relative_to(Path(directory) / "source") for p in Path(directory).rglob("*.xml")),
                            "Deployable metadata must belong to the declared source package for CLI bookkeeping.")

    def test_existing_connection_refused_before_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            sf = FakeSalesforce(directory, exists=True)
            with self.assertRaises(setup.SetupError):
                setup.perform_setup(sf, self.args())
            self.assertEqual([], sf.events)

    def test_failure_restores_original_flag_and_removes_temporary_access(self):
        for original in ("false", "true"):
            with self.subTest(original=original), tempfile.TemporaryDirectory() as directory:
                sf = FakeSalesforce(directory, original=original)
                with patch.object(setup, "create_application"), patch.object(setup, "create_connection"), \
                        patch.object(setup, "current_credentials", side_effect=setup.SetupError("Simulated secret read failure.")):
                    with self.assertRaises(setup.SetupError):
                        setup.perform_setup(sf, self.args())
                self.assertEqual(original, sf.settings[setup.SETTING])
                self.assertFalse(sf.assignment)
                self.assertFalse(sf.permission)
                if original == "true":
                    self.assertNotIn("Restore original REST consumer secret access", sf.events)

    def test_uncertain_assignment_is_rediscovered_and_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            sf = FakeSalesforce(directory)
            sf.uncertain_assignment = True
            with self.assertRaises(setup.SetupError):
                setup.perform_setup(sf, self.args())
            self.assertFalse(sf.assignment)
            self.assertFalse(sf.permission)
            self.assertEqual("false", sf.settings[setup.SETTING])

    def test_cleanup_error_preserves_only_sanitized_primary_error(self):
        with tempfile.TemporaryDirectory() as directory:
            sf = FakeSalesforce(directory)
            sf.uncertain_assignment = True
            with patch.object(sf, "delete_record", side_effect=RuntimeError("secret-do-not-print")):
                with self.assertRaises(setup.SetupError) as caught:
                    setup.perform_setup(sf, self.args())
            self.assertIn("Simulated interrupted assignment response", str(caught.exception))
            self.assertIn("Cleanup needs attention", str(caught.exception))
            self.assertNotIn("secret-do-not-print", str(caught.exception))

    def test_update_never_redeploys_existing_application_or_connection(self):
        with tempfile.TemporaryDirectory() as directory:
            sf = FakeSalesforce(directory, exists=True)
            with patch.object(setup, "validate_existing"), patch.object(setup, "create_application") as app, \
                    patch.object(setup, "create_connection") as connection, \
                    patch.object(setup, "current_credentials", return_value=("test-key", "test-secret")), \
                    patch.object(setup, "store_credentials"):
                result = setup.perform_setup(sf, self.args(update=True))
            app.assert_not_called()
            connection.assert_not_called()
            self.assertEqual("refresh-vault", result["mode"])
            self.assertNotIn("test-secret", json.dumps(result))
            self.assertNotIn("never-print-this-test-token", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
