#!/usr/bin/env python3
"""Provision OHM's Salesforce source connection without logging credential values.

Requires an explicitly authenticated Salesforce CLI target and an existing run-as
user. --update validates the existing connection and only refreshes its vault.
This module has no side effects on import; see test_setup_connection.py.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid
from urllib.parse import quote_plus, urlsplit
import xml.etree.ElementTree as ET


API = "67.0"
PREFIX = f"/services/data/v{API}/"
NS = "http://soap.sforce.com/2006/04/metadata"
APP = "Ohm_Source_Retrieval"
EXTERNAL = "Ohm_Salesforce_Auth"
NAMED = "Ohm_Salesforce"
PRINCIPAL = "SourceReader"
RUNTIME_PERMISSION = "Ohm_Source_Retrieval_API"
SETTING = "enableClientSecretInRestApiAccess"
ET.register_namespace("", NS)


class SetupError(Exception):
    """Messages are constructed locally; never embed raw CLI/API responses."""


class ApiError(SetupError):
    def __init__(self, status, code=None):
        self.status = status
        self.code = code
        super().__init__(f"Salesforce REST request failed (HTTP {status}"
                         + (f", {code}" if code else "") + ").")


def identifier(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9]{15}(?:[A-Za-z0-9]{3})?", value):
        raise SetupError("Salesforce returned an invalid record identifier.")
    return value


def soql(value):
    return value.replace("\\", "\\\\").replace("'", "\\'")


def api_path(value):
    """Accept only a same-org REST route, never a URL returned by another host."""
    parts = urlsplit(value)
    if parts.scheme or parts.netloc or parts.fragment or ".." in parts.path.split("/"):
        raise SetupError("Salesforce returned an unexpected API route.")
    path = parts.path.lstrip("/")
    if path.startswith("services/data/"):
        if not re.match(r"services/data/v\d+\.\d+/", path):
            raise SetupError("Salesforce returned an invalid API version route.")
        return "/" + path + ("?" + parts.query if parts.query else "")
    return PREFIX + path + ("?" + parts.query if parts.query else "")


def parse_rest_output(raw):
    # sf --include prints status, headers, then JSON without a blank separator.
    lines = raw.splitlines()
    if not lines or not re.fullmatch(r"HTTP/[\d.]+ \d{3}(?: .*)?", lines[0]):
        raise SetupError("Salesforce CLI did not return a recognizable HTTP status.")
    status = int(lines[0].split()[1])
    start = next((i for i, line in enumerate(lines[1:], 1)
                  if line.lstrip().startswith(("{", "["))), None)
    payload = None
    if start is not None:
        try:
            payload = json.loads("\n".join(lines[start:]))
        except (ValueError, TypeError):
            raise SetupError("Salesforce CLI returned an unreadable JSON response.") from None
    if status >= 400:
        first = payload[0] if isinstance(payload, list) and payload else payload
        code = first.get("errorCode") if isinstance(first, dict) else None
        code = code if isinstance(code, str) and re.fullmatch(r"[A-Z_]{1,80}", code) else None
        raise ApiError(status, code)
    if status < 200 or status >= 300:
        raise SetupError(f"Unexpected Salesforce response (HTTP {status}); redirects are not followed.")
    return payload


def deployment_diagnostics(payload, permission_details=False):
    """Allowlist job IDs, error names, and errors for our nonsecret temporary XML."""
    jobs = set()
    pending = [payload]
    while pending:
        value = pending.pop()
        if isinstance(value, dict):
            pending.extend(value.values())
        elif isinstance(value, list):
            pending.extend(value)
        elif isinstance(value, str) and re.fullmatch(r"0Af[A-Za-z0-9]{12}(?:[A-Za-z0-9]{3})?", value):
            jobs.add(value)
    names = []
    error_name = payload.get("name")
    if isinstance(error_name, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_.]{0,100}", error_name):
        names.append("CLI error " + error_name)
    if jobs:
        names.append("deployment " + ", ".join(sorted(jobs)))
    if permission_details:
        result = payload.get("result") or payload.get("data") or {}
        failures = (result.get("details") or {}).get("componentFailures") or []
        if isinstance(failures, dict):
            failures = [failures]
        for failure in failures:
            name = failure.get("fullName", "")
            if failure.get("componentType") == "PermissionSet" and re.fullmatch(r"Ohm_Source_Setup_[0-9a-f]{8}", name):
                problem = re.sub(r"[\x00-\x1f\x7f]", " ", str(failure.get("problem", "")))[:400]
                names.append(name + ": " + problem)
    return jobs, "; ".join(names)


class Salesforce:
    def __init__(self, target_org, directory):
        self.target_org = target_org
        self.directory = Path(directory)
        self.env = dict(os.environ)
        self.env.pop("DEBUG", None)
        self.env.update({"SF_DISABLE_LOG_FILE": "true", "SFDX_DISABLE_LOG_FILE": "true",
                         "SF_LOG_LEVEL": "fatal", "SFDX_LOG_LEVEL": "fatal",
                         "SF_DISABLE_TELEMETRY": "true", "SFDX_DISABLE_TELEMETRY": "true",
                         "SF_AUTOUPDATE_DISABLE": "true", "NO_COLOR": "1", "FORCE_COLOR": "0",
                         "SF_MDAPI_TEMP_DIR": str(self.directory / "mdapi")})
        self.steps = []

    def invoke(self, args, body=None):
        # shell=False and stdin keep secret parameters out of process arguments.
        try:
            result = subprocess.run(["sf", *args, "--target-org", self.target_org],
                                    input=body, text=True, capture_output=True,
                                    cwd=self.directory, env=self.env, timeout=720)
        except (OSError, subprocess.TimeoutExpired):
            raise SetupError("Salesforce CLI did not finish. Inspect the org's deployment status before retrying.") from None
        return result

    def command(self, args, label):
        result = self.invoke([*args, "--json"])
        try:
            payload = json.loads(result.stdout)
        except (ValueError, TypeError):
            raise SetupError(f"{label} did not return JSON; CLI output was suppressed.") from None
        if result.returncode or payload.get("status") != 0:
            _, diagnostic = deployment_diagnostics(payload)
            raise SetupError(f"{label} failed" + (f" ({diagnostic})" if diagnostic else "")
                             + "; raw CLI output was suppressed. Check Setup deployment history and permissions.")
        return payload.get("result")

    def rest(self, path, method="GET", body=None):
        args = ["api", "request", "rest", api_path(path), "--method", method, "--include"]
        if body is not None:
            args += ["--header", "Content-Type:application/json", "--body", "-"]
        result = self.invoke(args, json.dumps(body) if body is not None else None)
        return parse_rest_output(result.stdout)

    def query(self, query):
        result = self.command(["data", "query", "--query", query], "Metadata identity query")
        return result["records"]

    def delete_record(self, sobject, record_id):
        if sobject not in {"PermissionSet", "PermissionSetAssignment"}:
            raise SetupError("Cleanup refused an unexpected object type.")
        # The CLI REST plugin requires a body even for DELETE. The dedicated data
        # command handles Salesforce's empty 204 response without that code path.
        result = self.command(["data", "delete", "record", "--sobject", sobject,
                               "--record-id", identifier(record_id)], "Remove temporary " + sobject)
        if result.get("success") is not True:
            raise SetupError("Salesforce did not confirm temporary access removal.")

    def exists(self, metadata_type, name):
        result = self.command(["org", "list", "metadata", "--metadata-type", metadata_type,
                               "--api-version", API], "Metadata inventory")
        return any(item.get("fullName") == name for item in (result or []))

    def deploy(self, directory, label):
        raw = self.invoke(["project", "deploy", "start", "--source-dir", str(directory),
                           "--ignore-conflicts", "--wait", "10", "--api-version", API, "--json"])
        try:
            payload = json.loads(raw.stdout)
        except (ValueError, TypeError):
            raise SetupError(f"{label} returned unreadable CLI output; inspect deployment history before retrying.") from None
        result = payload.get("result") or {}
        if raw.returncode or payload.get("status") != 0:
            jobs, diagnostic = deployment_diagnostics(payload, label == "Create temporary setup permission")
            if len(jobs) == 1 and result.get("status") not in {"Failed", "Canceled"}:
                # CLI source-tracking/bookkeeping can fail after Salesforce commits.
                # A read-only report of this exact job is authoritative for success.
                result = self.command(["project", "deploy", "report", "--job-id", next(iter(jobs))],
                                      "Verify " + label)
            if result.get("status") != "Succeeded" or result.get("success") is not True:
                raise SetupError(f"{label} failed" + (f" ({diagnostic})" if diagnostic else "")
                                 + "; raw CLI output was suppressed. Inspect this deployment before retrying.")
        if result.get("status") != "Succeeded" or result.get("success") is not True:
            _, diagnostic = deployment_diagnostics(payload, label == "Create temporary setup permission")
            raise SetupError(f"{label} did not succeed" + (f" ({diagnostic})" if diagnostic else "")
                             + "; inspect deployment history before retrying.")
        self.steps.append({"step": label, "deploymentId": identifier(result["id"])})

    def retrieve(self, metadata_type, name, label):
        target = self.directory / ("read-" + uuid.uuid4().hex[:8])
        self.command(["project", "retrieve", "start", "--metadata", metadata_type + ":" + name,
                      "--target-metadata-dir", str(target), "--unzip", "--wait", "10",
                      "--api-version", API], label)
        return target


def xml_text(root, name):
    return root.findtext("{" + NS + "}" + name)


def read_component(directory, root_name):
    matches = []
    for path in Path(directory).rglob("*"):
        if not path.is_file() or path.suffix == ".zip":
            continue
        try:
            root = ET.parse(path).getroot()
        except (ET.ParseError, UnicodeError):
            continue
        if root.tag == "{" + NS + "}" + root_name:
            matches.append(root)
    if len(matches) != 1:
        raise SetupError(f"Could not unambiguously read {root_name} metadata.")
    return matches[0]


def write_xml(directory, relative, root_name, content):
    path = Path(directory) / relative
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    path.write_text(f'<?xml version="1.0" encoding="UTF-8"?>\n'
                    f'<{root_name} xmlns="{NS}">{content}</{root_name}>\n')
    path.chmod(0o600)
    return path


def tag(name, value):
    element = ET.Element(name)
    element.text = str(value)
    return ET.tostring(element, encoding="unicode")


def setting_values(sf):
    folder = sf.retrieve("Settings", "ExternalClientApp", "Read original external client app settings")
    root = read_component(folder, "ExternalClientAppSettings")
    raw = xml_text(root, SETTING)
    if raw not in ("true", "false"):
        raise SetupError("The original REST-secret access flag is unavailable; refusing to change it.")
    # Preserve and later compare every setting, not merely the modified flag.
    return {child.tag.rsplit("}", 1)[-1]: child.text for child in root}


def set_secret_access(sf, enabled, stage):
    directory = sf.directory / "source" / stage
    write_xml(directory, "settings/ExternalClientApp.settings-meta.xml", "ExternalClientAppSettings",
              tag(SETTING, enabled))
    sf.deploy(directory, stage)


def user(sf, username):
    records = sf.query("SELECT Id, Username, Email, IsActive FROM User WHERE Username = '" + soql(username) + "'")
    if len(records) != 1 or records[0].get("IsActive") is not True:
        raise SetupError("The specified Salesforce username must identify exactly one active user in the target org.")
    identifier(records[0]["Id"])
    return records[0]


def permission_id(sf, name):
    rows = sf.query("SELECT Id FROM PermissionSet WHERE Name = '" + soql(name) + "' AND IsOwnedByProfile = false")
    if len(rows) != 1:
        raise SetupError("The expected permission set is unavailable.")
    return identifier(rows[0]["Id"])


def assign(sf, user_id, perm_id):
    rows = sf.query("SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '" + identifier(user_id)
                    + "' AND PermissionSetId = '" + identifier(perm_id) + "'")
    if rows:
        return None  # Never remove a pre-existing assignment in cleanup.
    result = sf.rest("sobjects/PermissionSetAssignment", "POST",
                     {"AssigneeId": user_id, "PermissionSetId": perm_id})
    return identifier(result["id"])


def create_application(sf, run_as, email):
    folder = sf.directory / "source" / "application"
    write_xml(folder, f"externalClientApps/{APP}.eca-meta.xml", "ExternalClientApplication",
              tag("contactEmail", email) + tag("description", "OHM same-org metadata source retrieval")
              + tag("distributionState", "Local") + tag("isProtected", "false") + tag("label", "OHM Source Retrieval"))
    write_xml(folder, f"extlClntAppGlobalOauthSets/{APP}.ecaGlblOauth-meta.xml", "ExtlClntAppGlobalOauthSettings",
              tag("callbackUrl", "https://login.salesforce.com/services/oauth2/success")
              + tag("externalClientApplication", APP) + tag("isClientCredentialsFlowEnabled", "true")
              + tag("isConsumerSecretOptional", "false") + tag("isIntrospectAllTokens", "false")
              + tag("isPkceRequired", "true") + tag("isSecretRequiredForRefreshToken", "true")
              + tag("label", "OHM Source Retrieval OAuth")
              + tag("shouldRotateConsumerKey", "false") + tag("shouldRotateConsumerSecret", "false"))
    write_xml(folder, f"extlClntAppOauthSettings/{APP}.ecaOauth-meta.xml", "ExtlClntAppOauthSettings",
              tag("commaSeparatedOauthScopes", "Api") + tag("externalClientApplication", APP)
              + tag("label", "OHM Source Retrieval OAuth"))
    sf.deploy(folder, "Create external client app")
    folder = sf.directory / "source" / "policy"
    write_xml(folder, f"extlClntAppOauthPolicies/{APP}_defaultPolicy.ecaOauthPlcy-meta.xml", "ExtlClntAppOauthConfigurablePolicies",
              tag("clientCredentialsFlowUser", run_as) + tag("externalClientApplication", APP)
              + tag("ipRelaxationPolicyType", "Enforce") + tag("isClientCredentialsFlowEnabled", "true")
              + tag("isGuestCodeCredFlowEnabled", "false") + tag("isTokenExchangeFlowEnabled", "false")
              + tag("label", APP + "_defaultPolicy") + tag("permittedUsersPolicyType", "AllSelfAuthorized")
              + tag("refreshTokenPolicyType", "SpecificLifetime") + tag("refreshTokenValidityPeriod", "365")
              + tag("refreshTokenValidityUnit", "Days") + tag("requiredSessionLevel", "STANDARD"))
    sf.deploy(folder, "Configure fixed integration user")


def create_connection(sf, instance_url):
    folder = sf.directory / "source" / "connection"
    write_xml(folder, f"externalCredentials/{EXTERNAL}.externalCredential-meta.xml", "ExternalCredential",
              tag("authenticationProtocol", "Custom") + "<externalCredentialParameters>"
              + tag("parameterName", PRINCIPAL) + tag("parameterType", "NamedPrincipal")
              + tag("sequenceNumber", "1") + "</externalCredentialParameters>"
              + tag("label", "OHM Salesforce Source Authentication"))
    write_xml(folder, f"namedCredentials/{NAMED}.namedCredential-meta.xml", "NamedCredential",
              tag("allowMergeFieldsInBody", "true") + tag("allowMergeFieldsInHeader", "false")
              + tag("calloutStatus", "Enabled") + tag("generateAuthorizationHeader", "false")
              + tag("label", "OHM Salesforce Source") + "<namedCredentialParameters>"
              + tag("parameterName", "Url") + tag("parameterType", "Url") + tag("parameterValue", instance_url)
              + "</namedCredentialParameters><namedCredentialParameters>"
              + tag("externalCredential", EXTERNAL) + tag("parameterName", "Authentication")
              + tag("parameterType", "Authentication") + "</namedCredentialParameters>"
              + tag("namedCredentialType", "SecuredEndpoint"))
    write_xml(folder, f"permissionsets/{RUNTIME_PERMISSION}.permissionset-meta.xml", "PermissionSet",
              tag("description", "Allows OHM background audits to use the configured Salesforce source API connection.")
              + "<externalCredentialPrincipalAccesses>" + tag("enabled", "true")
              + tag("externalCredentialPrincipal", EXTERNAL + "-" + PRINCIPAL)
              + "</externalCredentialPrincipalAccesses>" + tag("label", "OHM Source Retrieval API"))
    sf.deploy(folder, "Create source connection and principal permission")


def validate_existing(sf, instance_url, run_as):
    policy = read_component(sf.retrieve("ExtlClntAppOauthConfigurablePolicies", APP + "_defaultPolicy", "Read integration policy"),
                            "ExtlClntAppOauthConfigurablePolicies")
    if xml_text(policy, "clientCredentialsFlowUser") != run_as or xml_text(policy, "isClientCredentialsFlowEnabled") != "true":
        raise SetupError("Existing ECA policy does not match --run-as or has client credentials disabled; --update never changes that policy.")
    named = read_component(sf.retrieve("NamedCredential", NAMED, "Read named credential definition"), "NamedCredential")
    params = named.findall("{" + NS + "}namedCredentialParameters")
    values = {xml_text(p, "parameterName"): p for p in params}
    if ("Url" not in values or xml_text(values["Url"], "parameterValue").rstrip("/") != instance_url
            or "Authentication" not in values or xml_text(values["Authentication"], "externalCredential") != EXTERNAL
            or xml_text(named, "generateAuthorizationHeader") != "false"
            or xml_text(named, "allowMergeFieldsInBody") != "true"
            or xml_text(named, "calloutStatus") != "Enabled"):
        raise SetupError("Existing named credential does not match OHM's same-org connection; --update will not replace it.")
    external = read_component(sf.retrieve("ExternalCredential", EXTERNAL, "Read external credential definition"), "ExternalCredential")
    principals = external.findall("{" + NS + "}externalCredentialParameters")
    if xml_text(external, "authenticationProtocol") != "Custom" or not any(
            xml_text(p, "parameterName") == PRINCIPAL and xml_text(p, "parameterType") == "NamedPrincipal" for p in principals):
        raise SetupError("Existing external credential does not have OHM's expected Custom named principal.")


def current_credentials(sf):
    apps = sf.rest("apps/oauth/usage")
    matches = [app for app in apps.get("apps", []) if app.get("developerName") == APP]
    if len(matches) != 1:
        raise SetupError("Expected exactly one OHM ECA in OAuth app inventory. Allow provisioning to finish and retry with --update.")
    app_id = identifier(matches[0]["identifier"])
    consumers = sf.rest("apps/oauth/credentials/" + app_id).get("consumers", [])
    if len(consumers) != 1:
        raise SetupError("Expected exactly one current OAuth consumer; select the correct app configuration before retrying.")
    consumer_id = identifier(consumers[0]["id"])
    path = api_path(consumers[0]["url"])
    # Do not follow staged credentials or an unrelated app/consumer route.
    selected = re.fullmatch(r"/services/data/v\d+\.\d+/apps/oauth/credentials/([A-Za-z0-9]+)/([A-Za-z0-9]+)", path)
    if (not selected or identifier(selected[1])[:15] != app_id[:15]
            or identifier(selected[2])[:15] != consumer_id[:15]):
        raise SetupError("The OAuth consumer URL does not match the selected ECA and current consumer.")
    key_result = sf.rest(path + "?part=key")
    secret_result = sf.rest(path + "?part=secret")
    if identifier(key_result.get("id"))[:15] != consumer_id[:15] or identifier(secret_result.get("id"))[:15] != consumer_id[:15]:
        raise SetupError("OAuth consumer identity changed while reading its current credentials.")
    key, secret = key_result.get("key"), secret_result.get("secret")
    if not isinstance(key, str) or not key or not isinstance(secret, str) or not secret:
        raise SetupError("Salesforce did not return the current consumer key and secret; verify temporary REST-secret access and permissions.")
    return key, secret


def vault_payload(key, secret):
    # Values are encoded before merge into the x-www-form-urlencoded token body.
    return {"externalCredential": EXTERNAL, "authenticationProtocol": "Custom",
            "principalName": PRINCIPAL, "principalType": "NamedPrincipal",
            "credentials": {"ClientIdEncoded": {"value": quote_plus(key), "encrypted": True},
                            "ClientSecretEncoded": {"value": quote_plus(secret), "encrypted": True}}}


def store_credentials(sf, key, secret, update):
    body = vault_payload(key, secret)
    exists = False
    try:
        current = sf.rest("named-credentials/credential?externalCredential=" + EXTERNAL
                          + "&principalName=" + PRINCIPAL + "&principalType=NamedPrincipal")
        if (current.get("externalCredential") != EXTERNAL or current.get("principalName") != PRINCIPAL
                or current.get("principalType") != "NamedPrincipal" or current.get("authenticationProtocol") != "Custom"):
            raise SetupError("The vault returned an unexpected credential identity; no credential was changed.")
        status = current.get("authenticationStatus")
        if status not in {"Configured", "NotConfigured", "Unknown"}:
            raise SetupError("The vault returned an unexpected authentication status; no credential was changed.")
        parameters = current.get("credentials")
        if not isinstance(parameters, dict) or set(parameters) - {"ClientIdEncoded", "ClientSecretEncoded"}:
            raise SetupError("The vault has unexpected authentication parameters; no credential was changed.")
        # Custom credentials can remain Unknown after successful authentication.
        # Names disclose whether material exists; their values are never inspected.
        exists = bool(parameters) or status == "Configured"
    except ApiError as ex:
        if ex.status != 404 or ex.code != "NOT_FOUND":
            raise
    if exists and not update:
        raise SetupError("The credential vault already exists; no values were overwritten. Use --update after reviewing its definition.")
    sf.rest("named-credentials/credential", "PUT" if exists else "POST", body)


def perform_setup(sf, args):
    display = sf.command(["org", "display"], "Read authenticated org identity")
    instance_url = display.get("instanceUrl", "").rstrip("/")
    setup_username = display.get("username")
    del display  # Never use, persist, or log the CLI session token returned by org display.
    parsed = urlsplit(instance_url)
    if parsed.scheme != "https" or not parsed.hostname or not parsed.hostname.endswith(".my.salesforce.com") or parsed.path:
        raise SetupError("The target must resolve to a Salesforce HTTPS My Domain URL.")
    setup_user = user(sf, setup_username)
    integration_user = user(sf, args.run_as)
    audit_users = [user(sf, name) for name in args.audit_user]
    reserved = [("ExternalClientApplication", APP), ("ExternalCredential", EXTERNAL),
                ("NamedCredential", NAMED), ("PermissionSet", RUNTIME_PERMISSION)]
    present = [sf.exists(kind, name) for kind, name in reserved]
    if args.update:
        if not all(present):
            raise SetupError("--update requires the complete existing OHM application and connection. Finish or remove partial setup manually first.")
        validate_existing(sf, instance_url, args.run_as)
    elif any(present):
        raise SetupError("Reserved OHM application or connection metadata already exists. Use --update only to refresh its existing vault.")
    original = setting_values(sf)
    permission_name = "Ohm_Source_Setup_" + uuid.uuid4().hex[:8]
    permission_created = False
    assignment_id = None
    perm_id = None
    setting_touched = False
    cleanup_errors = []
    primary_error = None
    try:
        access = sf.directory / "source" / "temporary-permission"
        permissions = ("ExternalClientAppDeveloper", "ViewClientSecret", "ExternalClientAppAdmin", "ExternalClientAppViewer")
        write_xml(access, f"permissionsets/{permission_name}.permissionset-meta.xml", "PermissionSet",
                  tag("label", "OHM Temporary Source Setup") + "".join(
                      "<userPermissions>" + tag("enabled", "true") + tag("name", name) + "</userPermissions>" for name in permissions))
        permission_created = True
        sf.deploy(access, "Create temporary setup permission")
        perm_id = permission_id(sf, permission_name)
        assignment_id = assign(sf, setup_user["Id"], perm_id)
        if not args.update:
            create_application(sf, args.run_as, args.contact_email or integration_user["Email"])
            create_connection(sf, instance_url)
        if original[SETTING] != "true":
            # Set before deploy so cleanup also runs after an uncertain deployment result.
            setting_touched = True
            set_secret_access(sf, "true", "Temporarily enable REST consumer secret access")
        key, secret = current_credentials(sf)
        try:
            store_credentials(sf, key, secret, args.update)
        finally:
            del key, secret
        if audit_users:
            runtime_id = permission_id(sf, RUNTIME_PERMISSION)
            for audit_user in audit_users:
                assign(sf, audit_user["Id"], runtime_id)
    except BaseException as ex:
        primary_error = ex
        raise
    finally:
        # Each cleanup runs independently, even if the preceding cleanup fails.
        if setting_touched:
            try:
                set_secret_access(sf, original[SETTING], "Restore original REST consumer secret access")
            except BaseException:
                cleanup_errors.append(f"Restore ExternalClientAppSettings.{SETTING} to {original[SETTING]} in target {sf.target_org}.")
        # A network failure can happen after assignment committed but before its ID
        # reached us. The permission name is unique to this invocation, so rediscover
        # only its assignment to the setup user before deleting the definition.
        if permission_created and assignment_id is None:
            try:
                if perm_id is None:
                    rows = sf.query("SELECT Id FROM PermissionSet WHERE Name = '" + permission_name + "' AND IsOwnedByProfile = false")
                    perm_id = identifier(rows[0]["Id"]) if rows else None
                if perm_id:
                    rows = sf.query("SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = '" + setup_user["Id"]
                                    + "' AND PermissionSetId = '" + perm_id + "'")
                    assignment_id = identifier(rows[0]["Id"]) if rows else None
            except BaseException:
                cleanup_errors.append(f"Check temporary permission assignments for {permission_name} in target {sf.target_org}.")
        if assignment_id:
            try:
                sf.delete_record("PermissionSetAssignment", assignment_id)
            except BaseException:
                cleanup_errors.append(f"Remove temporary PermissionSetAssignment {assignment_id} in target {sf.target_org}.")
        if permission_created and perm_id:
            try:
                # Safe to delete only this invocation's randomly named, unassigned definition.
                sf.delete_record("PermissionSet", perm_id)
            except BaseException:
                cleanup_errors.append(f"Delete temporary permission set {permission_name} after removing its assignment in target {sf.target_org}.")
        try:
            if setting_values(sf) != original:
                cleanup_errors.append(f"External Client App settings no longer match the original values in target {sf.target_org}; inspect concurrent changes.")
        except BaseException:
            cleanup_errors.append(f"Verify ExternalClientAppSettings.{SETTING} is {original[SETTING]} in target {sf.target_org}.")
        if cleanup_errors:
            # SetupError messages are ours and sanitized. Never interpolate an
            # arbitrary transport/library exception, which might contain secrets.
            cause = (str(primary_error) + " " if isinstance(primary_error, SetupError) else "")
            raise SetupError(cause + "Cleanup needs attention: " + " ".join(cleanup_errors)) from None
    return {"status": "Configured", "targetOrg": sf.target_org, "instanceUrl": instance_url,
            "runAs": args.run_as, "mode": "refresh-vault" if args.update else "create",
            "credentialValuesPrinted": False, "originalSettingsRestored": True,
            "temporarySetupPermissionRemoved": True, "deploymentSteps": sf.steps,
            "auditUsersGrantedPrincipalAccess": args.audit_user}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-org", required=True, help="Explicit sf org alias or username; no default org is used.")
    parser.add_argument("--run-as", required=True, help="Existing active integration user's exact Salesforce username.")
    parser.add_argument("--contact-email", help="ECA contact email; defaults to the run-as user's Email field.")
    parser.add_argument("--audit-user", action="append", default=[], help="During creation only: grant this exact username principal access (repeatable).")
    parser.add_argument("--update", action="store_true", help="Only refresh the current credential vault after validating existing definitions; never rotate.")
    args = parser.parse_args(argv)
    if args.update and args.audit_user:
        parser.error("--update only refreshes the vault; assign audit users separately.")
    if shutil.which("sf") is None:
        parser.error("Salesforce CLI (sf) must be installed and the target org authenticated.")
    old_umask = os.umask(0o077)
    previous_handler = signal.getsignal(signal.SIGTERM)
    signal.signal(signal.SIGTERM, lambda *_: (_ for _ in ()).throw(KeyboardInterrupt()))
    try:
        with tempfile.TemporaryDirectory(prefix="ohm-source-setup-") as folder:
            Path(folder).chmod(0o700)
            Path(folder, "sfdx-project.json").write_text(json.dumps({"packageDirectories": [{"path": "source", "default": True}],
                                                                   "sourceApiVersion": API}))
            Path(folder, "source").mkdir(mode=0o700)
            result = perform_setup(Salesforce(args.target_org, folder), args)
            print(json.dumps(result, indent=2))
        return 0
    except KeyboardInterrupt:
        print("Setup interrupted; cleanup ran where possible. Review any cleanup instructions above.", file=sys.stderr)
        return 130
    except SetupError as ex:
        print(str(ex), file=sys.stderr)
        return 1
    except Exception:
        # Library exceptions can contain response bodies or request parameters.
        print("Setup failed unexpectedly. Sensitive output was suppressed; inspect org deployment history before retrying.", file=sys.stderr)
        return 1
    finally:
        signal.signal(signal.SIGTERM, previous_handler)
        os.umask(old_umask)


if __name__ == "__main__":
    sys.exit(main())
