#!/usr/bin/env python3
"""Create an explicitly synthetic redundancy variant without modifying the upstream corpus."""
import difflib
import hashlib
import importlib.util
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'test-fixtures/public-agents/agent-script-recipes/force-app/main/02_actionConfiguration/actionDefinitions/aiAuthoringBundles/actionDefinitions/ActionDefinitions.agent'
OUTPUT=ROOT/'test-fixtures/controlled-weather'
REVISION='ac5ccac8f675153035370abbdce174e2b769c89c'
API='Ohm_Weather_Demo'
original=SOURCE.read_text()
clean=original.replace('developer_name: "ActionDefinitions"', f'developer_name: "{API}"').replace('agent_label: "Action Definitions"', 'agent_label: "Controlled Weather Demo"').replace('description: "Provides weather information by calling external weather APIs"', 'description: "Controlled audit demo derived from Salesforce weather recipe; intentional instruction redundancy is added only in the before variant"')
clean='# CONTROLLED AUDIT DEMO: renamed upstream weather recipe; see PROVENANCE.json.\n'+clean
needle='   reasoning:\n      instructions:->\n'
assert clean.count(needle)==1
paragraph='Help users get weather information for their requested locations and send weather alerts.'
redundancy=''.join('         | '+paragraph+'\n' for _ in range(36))
before=clean.replace(needle,needle+redundancy)
assert before.replace(redundancy,'',1)==clean
bundle='''<?xml version="1.0" encoding="UTF-8"?>
<AiAuthoringBundle xmlns="http://soap.sforce.com/2006/04/metadata"><bundleType>AGENT</bundleType><versionTag>v0.1</versionTag></AiAuthoringBundle>
'''
project={'packageDirectories':[{'path':'force-app','default':True}],'name':'ohm-controlled-weather','namespace':'','sourceApiVersion':'67.0','sfdcLoginUrl':'https://login.salesforce.com'}
for label,text in [('before',before),('after',clean)]:
    base=OUTPUT/label
    path=base/'force-app/main/default/aiAuthoringBundles'/API
    path.mkdir(parents=True,exist_ok=True)
    (path/f'{API}.agent').write_text(text)
    (path/f'{API}.bundle-meta.xml').write_text(bundle)
    (base/'sfdx-project.json').write_text(json.dumps(project,indent=2)+'\n')
patch=''.join(difflib.unified_diff(before.splitlines(True),clean.splitlines(True),fromfile='before/Ohm_Weather_Demo.agent',tofile='after/Ohm_Weather_Demo.agent'))
(OUTPUT/'remove-controlled-redundancy.patch').write_text(patch)
for candidate in ['LICENSE','LICENSE.txt']:
    license=ROOT/'test-fixtures/public-agents/agent-script-recipes'/candidate
    if license.exists(): (OUTPUT/'LICENSE').write_bytes(license.read_bytes());break
sha=lambda s:hashlib.sha256(s.encode()).hexdigest()
(OUTPUT/'PROVENANCE.json').write_text(json.dumps({'kind':'controlled demo variant, not an upstream defect','upstreamRepository':'https://github.com/trailheadapps/agent-script-recipes','upstreamCommit':REVISION,'upstreamPath':str(SOURCE.relative_to(ROOT)),'upstreamSha256':sha(original),'logicalAgentApiName':API,'changes':['Rename agent identity and add controlled-demo description/comment','Before only: repeat an existing weather instruction 36 times','After: remove only the intentional duplicate instruction lines; all upstream actions and branches unchanged'],'beforeSha256':sha(before),'afterSha256':sha(clean)},indent=2)+'\n')
spec=importlib.util.spec_from_file_location('importer',ROOT/'scripts/source/import-instructions.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
_,a=module.agent_script(OUTPUT/'before/force-app/main/default/aiAuthoringBundles'/API/f'{API}.agent')
_,b=module.agent_script(OUTPUT/'after/force-app/main/default/aiAuthoringBundles'/API/f'{API}.agent')
assert 2000<len(a['weather_lookup'])<8000
assert len(b['weather_lookup'])<2000
assert a['agent_router']==b['agent_router']
print(json.dumps({'beforeInstructionChars':len(a['weather_lookup']),'afterInstructionChars':len(b['weather_lookup']),'removedChars':len(a['weather_lookup'])-len(b['weather_lookup']),'beforeApproxTokens':(len(a['weather_lookup'])+3)//4,'afterApproxTokens':(len(b['weather_lookup'])+3)//4,'output':str(OUTPUT)},indent=2))
