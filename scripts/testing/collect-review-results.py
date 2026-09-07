#!/usr/bin/env python3
"""Read selected completed reviews and independently check their stored source evidence.

Does not run models or write Salesforce data. Output excludes complete source text.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--target-org', required=True)
parser.add_argument('--report-id', action='append', required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
if any(not re.fullmatch(r'[A-Za-z0-9]{15}(?:[A-Za-z0-9]{3})?', value) for value in args.report_id):
    parser.error('Each report ID must be a Salesforce record ID.')

def query(soql):
    run = subprocess.run(['sf', 'data', 'query', '--target-org', args.target_org,
                          '--query', soql, '--json'], capture_output=True, text=True, check=True)
    return json.loads(run.stdout)['result']['records']

def ids(values):
    return ','.join("'" + value + "'" for value in values)

def sha(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()

reports = query('SELECT Id, Target_Planner_Api_Name__c, Run_Status__c, Run_Stage_Message__c, '
                'Review_Result__c, Review_Summary__c, Source_Retrieval_Context__c '
                'FROM Agent_Audit_Report__c WHERE Id IN (' + ids(args.report_id) + ')')
checks = []
for report in reports:
    item = {'reportId': report['Id'], 'planner': report['Target_Planner_Api_Name__c'],
            'status': report['Run_Status__c'], 'stageMessage': report['Run_Stage_Message__c']}
    checks.append(item)
    if item['status'] != 'Complete' or not report['Review_Result__c']:
        item['verified'] = False
        continue
    review = json.loads(report['Review_Result__c'])
    summary = json.loads(report['Review_Summary__c'])
    snapshots = query('SELECT Artifact_Key__c, Source_Json__c, Source_Hash__c, Source_Binding_Verified__c '
                      "FROM Audit_Artifact_Snapshot__c WHERE Agent_Audit_Report__c = '" + report['Id'] + "'")
    by_key = {row['Artifact_Key__c']: row for row in snapshots}
    sources = {}
    artifact_checks = []
    for artifact in review['artifacts']:
        snapshot = by_key.get(artifact['artifactKey'], {})
        source = json.loads(snapshot['Source_Json__c']) if snapshot.get('Source_Json__c') else None
        valid = (source is not None and snapshot.get('Source_Binding_Verified__c') is True
                 and sha(source) == snapshot['Source_Hash__c'] == artifact['sourceHash']
                 and len(source.encode('utf-16-le')) // 2 == artifact['characterCount'])
        if valid:
            sources[artifact['artifactId']] = source
        artifact_checks.append({'artifactId': artifact['artifactId'], 'label': artifact['label'],
                                'characterCount': artifact['characterCount'], 'sourceHash': artifact['sourceHash'],
                                'sourceVersion': artifact['sourceVersion'], 'verified': valid,
                                'ratings': {c['id']: c['rating'] for c in artifact['categories']}})
    state = json.loads(report['Source_Retrieval_Context__c'])
    source_ids = state.get('sourceIds', [])
    configurations = {}
    if source_ids:
        manifests = query('SELECT Planner_Id__c, Manifest__c FROM Ohm_Instruction_Source__c WHERE Id IN (' + ids(source_ids) + ')')
        for row in manifests:
            manifest = json.loads(row['Manifest__c'])
            configurations['configuration:' + row['Planner_Id__c']] = manifest
    context_checks = []
    for context in review.get('contextSources', []):
        manifest = configurations.get(context['artifactId'], {})
        source = manifest.get('configurationSource')
        valid = source is not None and sha(source) == context['sourceHash'] == manifest.get('configurationSourceHash')
        if valid:
            sources[context['artifactId']] = source
        context_checks.append({'artifactId': context['artifactId'], 'verified': valid})
    all_categories = review['categories'] + [c for a in review['artifacts'] for c in a['categories']]
    quotes = [q for c in all_categories for i in c['issues'] for q in i['evidence']]
    valid_quotes = all(q['artifactId'] in sources and q['quote'] and q['quote'] in sources[q['artifactId']] for q in quotes)
    compact_matches = summary['categories'] == review['categories'] and summary.get('summaryOnly') is True and summary['artifacts'] == []
    item.update({'reviewerModel': review.get('reviewerModel'), 'reviewerTemplate': review['reviewerTemplate'],
                 'declaredReviewerVersion': review['reviewerVersion'], 'reviewedAt': review['reviewedAt'],
                 'coverage': review['coverage'], 'categories': review['categories'],
                 'artifacts': artifact_checks, 'configurationSources': context_checks,
                 'quotedEvidenceCount': len(quotes), 'allQuotesMatchStoredSources': valid_quotes,
                 'fleetSummaryMatchesDetail': compact_matches,
                 'verified': bool(artifact_checks) and all(a['verified'] for a in artifact_checks)
                             and all(c['verified'] for c in context_checks) and valid_quotes and compact_matches})
output = {'collectedAt': datetime.now(timezone.utc).isoformat(), 'targetOrg': args.target_org,
          'requestedReportCount': len(args.report_id), 'returnedReportCount': len(reports), 'reports': checks}
output['allVerified'] = len(reports) == len(args.report_id) and all(r['verified'] for r in checks)
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(output, indent=2) + '\n')
print(json.dumps({'output': str(args.output), 'allVerified': output['allVerified'],
                  'reports': [{'planner': r['planner'], 'status': r['status'], 'verified': r['verified']} for r in checks]}))
raise SystemExit(0 if output['allVerified'] else 1)
