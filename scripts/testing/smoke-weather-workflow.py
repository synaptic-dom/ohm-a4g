#!/usr/bin/env python3
"""Exercise the published controlled weather fixture with Salesforce's official evaluator.

The five cases are independent sessions. Weather actions are fixed-data reference stubs;
the alert case only formats text in the verified stub and never delivers a message. Existing result import supports
saving evidence without repeating model calls.
"""
import argparse
import hashlib
import json
import subprocess
from datetime import datetime,timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SPEC=ROOT/'test-fixtures/controlled-weather/workflow-smoke.json'
CASES=['missing-location','current-weather','forecast','out-of-scope','weather-alert']

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target-org',default='ohm-audit-lab')
    parser.add_argument('--planner-api-name',required=True)
    parser.add_argument('--phase',choices=['before','after'],required=True)
    parser.add_argument('--source-file',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--existing-eval-result',type=Path)
    args=parser.parse_args()
    if not args.planner_api_name.startswith('Ohm_Weather_Demo_v'):
        parser.error('This runner is restricted to the controlled Ohm_Weather_Demo fixture')
    evidence={'recordedAt':datetime.now(timezone.utc).isoformat(),'phase':args.phase,'orgAlias':args.target_org,
              'agentApiName':'Ohm_Weather_Demo','plannerApiName':args.planner_api_name,
              'sourceSha256':hashlib.sha256(args.source_file.read_bytes()).hexdigest(),
              'mode':'published Agent API through sf agent test run-eval',
              'spec':str(SPEC.relative_to(ROOT)),
              'executionNotes':['Five independent sessions; expected outcomes scored by the Salesforce bot_response_rating evaluator.',
                'Weather Flows return fixed reference values; these are not real weather observations.',
                'The alert action formats a string only. No external weather call, email, payment, or business-record change is part of these cases.',
                'Publication/activation is managed separately; run against the stated active version before changing it.']}
    if args.existing_eval_result:
        reply=json.loads(args.existing_eval_result.read_text())
        evidence['executedAt']=datetime.fromtimestamp(args.existing_eval_result.stat().st_mtime,timezone.utc).isoformat()
    else:
        evidence['executedAt']=datetime.now(timezone.utc).isoformat()
        process=subprocess.run(['sf','agent','test','run-eval','--api-name','Ohm_Weather_Demo','--target-org',args.target_org,
              '--spec',str(SPEC),'--api-version','67.0','--result-format','json','--json'],capture_output=True,text=True,cwd=ROOT)
        try:reply=json.loads(process.stdout)
        except json.JSONDecodeError:reply={'status':process.returncode or 1,'message':'CLI response was not valid JSON'}
    evidence['status']=reply.get('status');evidence['error']=reply.get('message')
    result=reply.get('result',{});evidence['summary']=result.get('summary',{})
    cases=[]
    trace_assertions=[]
    def functions(value):
        if isinstance(value,list):
            return [fn for child in value for fn in functions(child)]
        if isinstance(value,dict) and isinstance(value.get('function'),dict):
            return [value['function']]
        return []
    for index,test in enumerate(result.get('tests',[])):
        item={'case':CASES[index] if index<len(CASES) else test.get('id'), 'status':test.get('status'),
              'responses':[output.get('response') for output in test.get('outputs',[]) if output.get('type')=='agent.send_message'],
              'evaluations':test.get('evaluations',[])}
        if item['case']=='weather-alert':
            observed=[]
            for output in test.get('outputs',[]):
                if output.get('type')=='agent.get_state':
                    state=output.get('response',{}).get('planner_response',{}).get('lastExecution',{})
                    observed=functions(state.get('invokedActions'))
            # Historical probe compatibility: preserve, rather than erase, its remote shape error.
            if not observed:
                for evaluation in test.get('evaluations',[]):
                    if evaluation.get('type')=='evaluator.planner_actions_assertion':
                        observed=functions(evaluation.get('actual_value'))
            passed=len(observed)==1 and observed[0].get('name')=='send_weather_alert' and observed[0].get('input',{}).get('message')=='Light rain expected in San Francisco' and observed[0].get('input',{}).get('severity','').lower()=='low' and observed[0].get('output',{}).get('__action_execution_status__')=='success' and observed[0].get('output',{}).get('alertMessage')=='Weather Alert: Light rain expected in San Francisco Severity: low'
            trace_assertions.append({'case':'weather-alert','passed':passed,'expectedFunction':'send_weather_alert',
                'observedFunctions':[{'name':fn.get('name'),'input':fn.get('input'),'executionStatus':fn.get('output',{}).get('__action_execution_status__'),'alertMessage':fn.get('output',{}).get('alertMessage')} for fn in observed]})
        ratings=[e for e in test.get('evaluations',[]) if e.get('type')=='evaluator.bot_response_rating']
        item['responsePassed']=len(ratings)==1 and ratings[0].get('is_pass') is True
        cases.append(item)
    evidence['cases']=cases
    evidence['directTraceAssertions']=trace_assertions
    evidence['responseCaseSummary']={'passed':sum(case['responsePassed'] for case in cases),'total':len(CASES)}
    evidence['directTraceSummary']={'passed':sum(check['passed'] for check in trace_assertions),'total':1}
    summary=evidence['summary']
    evidence['outcome']='Passed' if reply.get('status')==0 and len(cases)==len(CASES) and all(c['status']=='passed' and c['responsePassed'] for c in cases) and len(trace_assertions)==1 and trace_assertions[0]['passed'] and summary.get('errors')==0 else 'NeedsReview'
    if len(cases)==len(CASES) and all(c['responsePassed'] for c in cases) and len(trace_assertions)==1 and trace_assertions[0]['passed'] and summary.get('failed')==1 and summary.get('errors')==0:
        evidence['outcome']='Responses pass; action trace confirmed; evaluator mismatch retained'
        evidence['evaluatorLimitation']='planner_actions_assertion receives nested function objects instead of action-name strings and fails even when the exact function succeeds. Its failure remains in summary and evaluations; the independent trace assertion checks name, inputs, successful execution, and output.'
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(evidence,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({'outcome':evidence['outcome'],'summary':summary,'output':str(args.output.resolve())}),flush=True)

if __name__=='__main__':main()
