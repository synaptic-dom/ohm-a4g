#!/usr/bin/env python3
"""Import explicitly versioned static agent source for one published Salesforce planner.

Reads only local source and org inventory; --apply writes an Ohm source snapshot, not metadata.
Agent Script blocks retain conditional DSL (static source size, not measured rendered tokens).
Unknown topic mappings or unparsed instruction forms fail closed; no heuristic source assignment.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import subprocess
import tempfile
import textwrap
from datetime import datetime
from pathlib import Path
from xml.etree import ElementTree as ET

NS = '{http://soap.sforce.com/2006/04/metadata}'

def digest(value: str) -> str:
    return hashlib.sha256(value.encode('utf-8')).hexdigest()

def sf_json(*args: str) -> dict:
    command = subprocess.run(['sf', *args, '--json'], text=True, capture_output=True)
    try:
        result = json.loads(command.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError('Salesforce CLI did not return JSON; retry the command separately.') from exc
    if result.get('status') != 0:
        raise RuntimeError(result.get('message', 'Salesforce CLI request failed'))
    return result['result']

def instructions_in_block(block: str) -> str | None:
    lines = block.splitlines()
    found = []
    for index, line in enumerate(lines):
        match = re.match(r'^(\s*)instructions\s*:\s*(.*?)\s*$', line)
        if not match:
            continue
        indent = len(match[1]); value = match[2]
        if value.startswith(('"', "'")):
            if value.startswith('"'):
                try: found.append(json.loads(value))
                except json.JSONDecodeError as exc: raise ValueError('Unsupported quoted instruction format') from exc
            else:
                if not value.endswith("'"): raise ValueError('Unclosed single-quoted instruction')
                found.append(value[1:-1].replace("''", "'"))
            continue
        if value not in ('|', '->'):
            raise ValueError(f'Unsupported instruction expression: {value}')
        following = []
        for next_line in lines[index+1:]:
            if next_line.strip() and len(next_line)-len(next_line.lstrip()) <= indent:
                break
            following.append(next_line)
        if not any(line.strip() for line in following):
            raise ValueError('Empty indented instruction block')
        found.append(textwrap.dedent('\n'.join(following)).rstrip())
    return '\n\n'.join(found) if found else None

def agent_script(path: Path) -> tuple[str, dict[str, str]]:
    source = path.read_text()
    sections = list(re.finditer(r'^(system|start_agent\s+[A-Za-z_][\w]*|subagent\s+[A-Za-z_][\w]*)\s*:\s*$', source, re.M))
    system = ''; topics = {}
    for i, match in enumerate(sections):
        end = sections[i+1].start() if i+1 < len(sections) else len(source)
        text = instructions_in_block(source[match.end():end])
        name = match.group(1)
        if name == 'system': system = text or ''
        elif text is not None: topics[name.split()[1]] = text
        else: raise ValueError(f'No instruction source for {name}')
    if not topics: raise ValueError('No supported Agent Script topics found')
    return system, topics

def legacy_plugin(path: Path) -> tuple[str, str]:
    root = ET.parse(path).getroot()
    api = root.findtext(NS+'developerName') or path.name.split('.')[0]
    instructions = [node.findtext(NS+'description') or '' for node in root.findall(NS+'genAiPluginInstructions')]
    if not instructions or any(not item.strip() for item in instructions):
        raise ValueError(f'No complete nested instructions in {path}')
    return api, '\n\n'.join(instructions)

def prompt_template(path: Path) -> tuple[str, str, str, str]:
    root = ET.parse(path).getroot()
    api = root.findtext(NS+'developerName') or path.name.split('.')[0]
    active = root.findtext(NS+'activeVersionIdentifier')
    versions = root.findall(NS+'templateVersions')
    matches = [v for v in versions if v.findtext(NS+'versionIdentifier') == active] if active else []
    if len(matches) != 1:
        raise ValueError(f'Cannot resolve one active prompt version for {api}')
    version = matches[0]
    content = version.findtext(NS+'content')
    if content is None: raise ValueError(f'Active prompt version has no content: {api}')
    return api, content, version.findtext(NS+'primaryModel') or '', active

def source_artifact(row: dict, instructions: str, path: Path, block: str, kind: str, revision: str, model: str | None = None) -> dict:
    return dict(id=row['Id'], instructions=instructions, sourceKind=kind,
                sourceVersion=f'{revision}:{digest(path.read_text())}', sourceHash=digest(instructions),
                sourcePath=f'{path.resolve()}#{block}', boundModel=model)

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--target-org', required=True)
    parser.add_argument('--planner-api-name', required=True)
    parser.add_argument('--source-revision', required=True, help='Pinned commit, immutable release, or documented controlled revision')
    parser.add_argument('--agent-script', type=Path)
    parser.add_argument('--legacy-plugin', action='append', type=Path, default=[])
    parser.add_argument('--prompt-template', action='append', type=Path, default=[])
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--apply', action='store_true', help='Append source manifest in Ohm (does not deploy or publish source)')
    args = parser.parse_args()
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', args.planner_api_name):
        parser.error('Planner API name must be an identifier')
    if bool(args.agent_script) == bool(args.legacy_plugin):
        parser.error('Choose either --agent-script or one or more --legacy-plugin files')
    def query(soql: str) -> list[dict]:
        return sf_json('data', 'query', '--target-org', args.target_org, '--query', soql)['records']
    planners = query(f"SELECT Id,DeveloperName,LastModifiedDate FROM GenAiPlannerDefinition WHERE DeveloperName = '{args.planner_api_name}'")
    if len(planners) != 1: raise ValueError('Exactly one published planner must match')
    planner = planners[0]; pid = planner['Id']
    topics = query(f"SELECT Id,DeveloperName,PlannerId,LastModifiedDate FROM GenAiPluginDefinition WHERE PlannerId = '{pid}'")
    topic_ids = ','.join("'"+row['Id']+"'" for row in topics)
    where = f"PlannerId = '{pid}'" + (f' OR PluginId IN ({topic_ids})' if topic_ids else '')
    actions = query('SELECT Id,DeveloperName,PlannerId,PluginId,InvocationTargetType,InvocationTarget,LastModifiedDate FROM GenAiFunctionDefinition WHERE '+where)
    if not topics: raise ValueError('No authoritative topic relationships; import an explicit legacy mapping before claiming legacy coverage')
    rows = [planner, *topics, *actions]
    versions = sorted(row['Id']+':'+str(round(datetime.fromisoformat(row['LastModifiedDate'].replace('Z','+00:00')).timestamp()*1000)) for row in rows)
    manifest = dict(schemaVersion=1, plannerId=pid, plannerApiName=args.planner_api_name,
                    metadataFingerprint=digest('\n'.join(versions)), sourceRevision=args.source_revision,
                    artifacts=[], warnings=[])
    if args.agent_script:
        config = args.agent_script.read_text()
        source_name = re.search(r'^\s*developer_name:\s*[\'"]([^\'"]+)[\'"]', config, re.M)
        if not source_name or re.sub(r'_v\d+$','',args.planner_api_name) != source_name.group(1):
            raise ValueError('Agent Script developer_name does not match the selected planner')
        system, source_topics = agent_script(args.agent_script)
        manifest['artifacts'].append(source_artifact(planner,system,args.agent_script,'system','ImportedAgentScript',args.source_revision))
        for topic in topics:
            # Generated suffix is the owning planner's Salesforce Id, never a name similarity join.
            name = re.sub('_'+re.escape(pid[:15])+r'$', '', topic['DeveloperName'])
            if name not in source_topics:
                raise ValueError(f'Published topic has no exact source block: {topic["DeveloperName"]}')
            manifest['artifacts'].append(source_artifact(topic,source_topics[name],args.agent_script,name,'ImportedAgentScript',args.source_revision))
        if set(source_topics) != {re.sub('_'+re.escape(pid[:15])+r'$', '', t['DeveloperName']) for t in topics}:
            raise ValueError('Source includes unpublished topics; import the source matching this exact publication')
        manifest['warnings'].append('Imported Agent Script is versioned static source; conditional branches are retained. Source size is not measured rendered prompt usage.')
    else:
        plugins = {legacy_plugin(path)[0]: (path,legacy_plugin(path)[1]) for path in args.legacy_plugin}
        for topic in topics:
            if topic['DeveloperName'] not in plugins: raise ValueError('Missing exact legacy plugin source: '+topic['DeveloperName'])
            path, text = plugins[topic['DeveloperName']]
            manifest['artifacts'].append(source_artifact(topic,text,path,'genAiPluginInstructions','ImportedLegacyPlugin',args.source_revision))
        manifest['warnings'].append('Legacy plugin instructions imported; planner-level system instructions and execution graph remain unavailable.')
    templates = {}
    for path in args.prompt_template:
        name,text,model,version = prompt_template(path)
        if name in templates: raise ValueError('Duplicate prompt template: '+name)
        templates[name] = (path,text,model,version)
    metadata_names = {}
    if any((action['InvocationTargetType'] or '').strip().lower() in ('prompt','generatepromptresponse') for action in actions):
        for component in sf_json('org','list','metadata','--metadata-type','GenAiPromptTemplate','--target-org',args.target_org):
            metadata_names[component['id']] = component['fullName']
    for action in actions:
        if (action['InvocationTargetType'] or '').strip().lower() not in ('prompt','generatepromptresponse'): continue
        raw_target = (action['InvocationTarget'] or '').split('://')[-1]
        target = metadata_names.get(raw_target, raw_target)
        if target not in templates: raise ValueError('Supply active prompt source for '+target)
        path,text,model,version = templates[target]
        manifest['artifacts'].append(source_artifact(action,text,path,'templateVersions/'+version,'ImportedPromptTemplate',args.source_revision,model))
        manifest['warnings'].append('Prompt template '+target+' is an imported source snapshot; current binding cannot be verified through planner metadata. Model assumption remains explicit.')
    args.output.parent.mkdir(parents=True,exist_ok=True)
    encoded = json.dumps(manifest,ensure_ascii=False,separators=(',',':'))
    args.output.write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
    result = dict(plannerApiName=args.planner_api_name, artifacts=len(manifest['artifacts']), metadataFingerprint=manifest['metadataFingerprint'], manifest=str(args.output.resolve()), applied=False)
    if args.apply:
        if len(encoded)>131072: raise ValueError('Source manifest exceeds the 131072 character storage limit')
        import base64
        value = base64.b64encode(encoded.encode()).decode()
        # Each Apex literal stays small; source never becomes executable code.
        literal = '+\n'.join("'"+value[i:i+8000]+"'" for i in range(0,len(value),8000))
        apex = 'String source = EncodingUtil.base64Decode('+literal+").toString();\nSystem.debug('OHM_SOURCE_IMPORTED '+OhmSourceImportService.importBundle(source));\n"
        with tempfile.NamedTemporaryFile('w',suffix='.apex') as handle:
            handle.write(apex); handle.flush()
            execution = sf_json('apex','run','--target-org',args.target_org,'--file',handle.name)
        if not execution.get('compiled') or not execution.get('success'):
            raise RuntimeError(execution.get('exceptionMessage') or execution.get('compileProblem') or 'Source import failed')
        result['applied'] = True
    print(json.dumps(result,indent=2))

if __name__ == '__main__':
    main()
