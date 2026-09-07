#!/usr/bin/env python3
"""Check local source links, exact provenance, template inputs and Ohm extraction. No org access."""
import hashlib
import importlib.util
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
BASE = Path(__file__).resolve().parents[1]
ROOT = BASE.parents[1]
META = BASE / 'force-app/main/default'
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}
spec = importlib.util.spec_from_file_location('source_parser', ROOT / 'scripts/source/import-instructions.py')
parser = importlib.util.module_from_spec(spec); spec.loader.exec_module(parser)
manifest = json.loads((BASE / 'PROVENANCE.json').read_text())
for item in manifest['files']:
    actual = hashlib.sha256((BASE / item['path']).read_bytes()).hexdigest()
    assert actual == item['sha256'], f"Source hash changed: {item['path']}"
for path in META.rglob('*.xml'): ET.parse(path)
templates = {}
for path in (META / 'genAiPromptTemplates').glob('*.xml'):
    template = ET.parse(path).getroot()
    name = template.findtext('m:developerName', namespaces=NS)
    content = template.findtext('m:templateVersions/m:content', namespaces=NS)
    input_name = template.findtext('m:templateVersions/m:inputs/m:apiName', namespaces=NS)
    assert '{!$Input:' + input_name + '}' in content
    assert template.findtext('m:activeVersionIdentifier', namespaces=NS) == template.findtext('m:templateVersions/m:versionIdentifier', namespaces=NS)
    assert template.findtext('m:templateVersions/m:status', namespaces=NS) == 'Published'
    templates[name] = {'chars': len(content), 'input': input_name}
assert len(templates) == 4
result = []
for fixture in manifest['fixtures']:
    path = META / 'aiAuthoringBundles' / fixture['api'] / (fixture['api'] + '.agent')
    text = path.read_text()
    api_name = re.search(r'developer_name: "([^"]+)"', text).group(1)
    system, topics = parser.agent_script(path)
    blocks = {'system': system, **topics}
    assert api_name == fixture['api']
    assert len(blocks) == 3 and all(value and value.strip() for value in blocks.values()), (api_name, blocks.keys())
    references = re.findall(r'target: "generatePromptResponse://([^"\n]+)"', text)
    assert references == [fixture['template']], (api_name, references)
    for reference in references:
        assert f'"Input:{templates[reference]["input"]}": string' in text
    assert sum(map(len, blocks.values())) < 8000
    result.append({'bundle': api_name, 'instructionBlocks': len(blocks), 'instructionChars': sum(map(len, blocks.values())), 'linkedPrompt': fixture['template'], 'linkedPromptChars': templates[fixture['template']]['chars']})
control = (META / 'aiAuthoringBundles/Ohm_Schedule_Desk/Ohm_Schedule_Desk.agent').read_text()
assert 'target: "apex://OhmDemoScheduleService"' in control
assert 'run @actions.present_schedule' in control
assert 'with "Input:validatedPlan" = @variables.validated_plan' in control
print(json.dumps({'localChecks': 'Passed', 'platformCompilation': 'Not run by this check', 'fixtures': result}, indent=2))
