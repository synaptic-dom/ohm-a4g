#!/usr/bin/env python3
"""Materialize isolated controlled event fixtures. Never contacts or changes a Salesforce org."""
import base64
import hashlib
import json
import shutil
import xml.etree.ElementTree as ET
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
ROOT = BASE.parents[1]
META = BASE / 'force-app/main/default'
NS = 'http://soap.sforce.com/2006/04/metadata'
ET.register_namespace('', NS)
UPSTREAM = ROOT / 'test-fixtures/public-agents/agent-script-recipes'
sha = lambda data: hashlib.sha256(data).hexdigest()
# Sept 7, 2026: the hackathon trial org (00Daj000013wTtpEAE) is not licensed for the
# AgentforceEmployeeAgent template (publish returns HTTP 401 "no access to agent templates
# associated with the AgentforceEmployeeAgent agent type"). It does hold Service Agent
# Builder/User licenses, so the fixtures publish as AgentforceServiceAgent with a dedicated
# Einstein Agent User. That user exists only in the hackathon org; recreate it before
# publishing anywhere else (Einstein Agent User profile + AgentforceServiceAgentBase,
# AgentforceServiceAgentUser, EinsteinGPTPromptTemplateUser, Ohm_Event_Fixture_Access).
AGENT_TYPE = 'AgentforceServiceAgent'
DEFAULT_AGENT_USER = 'ohm.fixture.agent@orgfarm-08e0e83a93.ohm'
# Sept 7, 2026 (user decision): no GPT-4o mini; the linked prompts use the newest alias that generates in
# the hackathon org (probed via the Models API). The model is part of the version identifier so a model
# change publishes a new prompt version instead of mutating an existing published one.
PROMPT_MODEL = 'sfdc_ai__DefaultGPT55'

def save_xml(path, element):
    path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(element, space='    ')
    ET.ElementTree(element).write(path, encoding='UTF-8', xml_declaration=True)

def node(parent, name, text=None):
    element = ET.SubElement(parent, f'{{{NS}}}{name}')
    if text is not None: element.text = text
    return element

def prompt(api, label, input_api, input_label, content):
    version = base64.b64encode(hashlib.sha256((api + '\n' + PROMPT_MODEL + '\n' + content).encode()).digest()).decode() + '_1'
    element = ET.Element(f'{{{NS}}}GenAiPromptTemplate')
    node(element, 'activeVersionIdentifier', version)
    node(element, 'description', f'Controlled event fixture: {label}. Uses synthetic user-supplied text; does not send messages or update records.')
    node(element, 'developerName', api); node(element, 'masterLabel', label)
    template = node(element, 'templateVersions'); node(template, 'content', content)
    input_node = node(template, 'inputs')
    for name, text in [('apiName', input_api), ('definition', 'primitive://String'), ('masterLabel', input_label), ('referenceName', 'Input:' + input_api), ('required', 'true')]: node(input_node, name, text)
    node(template, 'primaryModel', PROMPT_MODEL)
    node(template, 'status', 'Published'); node(template, 'versionIdentifier', version)
    node(element, 'type', 'einstein_gpt__flex'); node(element, 'visibility', 'Global')
    save_xml(META / 'genAiPromptTemplates' / f'{api}.genAiPromptTemplate-meta.xml', element)

POLICY = 'For a damaged item reported within thirty days, ask for the order reference and a photo of the damage, then explain the replacement review. A specialist decides eligibility; do not promise a refund or replacement approval. Do not request card details.'
support = '''You work for Juniper Outdoor customer support. Draft one helpful reply to the customer message below. Use the supplied policy, acknowledge the problem, and give the next step. Do not invent an order status, approval, or previous contact. Keep the reply within a short paragraph and a short list of requested information.

Customer message:
{!$Input:customerMessage}

Support policy:
''' + '\n\n'.join([POLICY] * 6) + '\n'
sales = '''You are an account executive at Aster Works. The rep needs a follow-up email they can review after a product discovery call. Use only the supplied meeting notes; do not invent pricing, promises, customer statements, or a booked appointment. Do not send anything.

Meeting notes:
{!$Input:meetingNotes}

Deliverable requirements:
Write eight complete alternatives to the follow-up email, even when the rep requested only one draft. Give every alternative a long introduction, a detailed recap of every meeting note, the proposed next step, and a long closing. After the eight alternatives, repeat the selected email in plain text, Markdown, HTML, and a JSON object with the entire body. Add a paragraph explaining the stylistic choices for each alternative. The rep will copy only the selected plain-text email into their email editor; no downstream system consumes the other formats or explanations.
'''
schedule = '''You are the guest coordinator at Cedar Bay Retreat. Create a day plan from the supplied activities. Each line contains HH:MM|duration minutes|activity name|location. The activities are already selected for the guest's interests.

Activities:
{!$Input:activities}

Calculate each activity's end time from its start time and duration. Sort the activities by start time. Select the earliest activity, then include the next activity only when it starts at least sixty minutes after the previous included activity ends. Check overlaps and the minimum free-time gap yourself. Preserve input order for equal start times. If an input line is malformed or an activity extends beyond the day, ask for corrected input rather than guessing.

Return one short schedule in chronological order with each activity's name, start and end time, location, and duration. Briefly list activities omitted because of overlap or insufficient free time. Invite the guest to contact the desk to book; do not claim a reservation was made.
'''
presentation = '''You are the guest coordinator at Cedar Bay Retreat. Turn the validated plan below into a welcoming, concise guest-facing message. The preparation action has already validated input, sorted activities, checked overlap, and enforced the minimum gap.

Validated preparation output:
{!$Input:validatedPlan}

Preserve every supplied activity, time, location, omission, and validation message. Do not calculate times, reorder activities, add a new activity, or repeat the preparation checks. If the preparation output requests corrected input, relay that request and do not propose a schedule. Use one short greeting, the provided plan, and a brief invitation to contact the desk to book. Do not claim a reservation was made. Return only that message.
'''
SPECS = [
    dict(api='Ohm_Support_Desk', label='Customer Support', topic='customer_support', template='Ohm_Support_Reply', templateLabel='Draft Customer Support Reply', input='customerMessage', inputLabel='Customer message', role='a customer support assistant for Juniper Outdoor', purpose='Draft a support reply using the supplied customer message and replacement policy.', action='draft_support_reply', content=support, expected='INPUT_REDUNDANCY'),
    dict(api='Ohm_Sales_Follow_Up', label='Sales Follow-up', topic='sales_follow_up', template='Ohm_Sales_Follow_Up_Email', templateLabel='Draft Sales Follow-up Email', input='meetingNotes', inputLabel='Meeting notes', role='a sales writing assistant for Aster Works', purpose='Draft a follow-up email from the meeting notes the rep supplies.', action='draft_follow_up', content=sales, expected='OUTPUT_UNNECESSARY_VERBOSITY or OUTPUT_FORMAT_MISMATCH'),
    dict(api='Ohm_Schedule_Planner', label='Schedule Planning', topic='schedule_planning', template='Ohm_Plan_Day', templateLabel='Plan a Guest Day', input='activities', inputLabel='Activity rows', role='a guest scheduling assistant for Cedar Bay Retreat', purpose='Prepare a day plan from the activity rows supplied by the guest coordinator.', action='plan_day', content=schedule, expected='CALLS_DETERMINISTIC_ALTERNATIVE'),
]

def simple_agent(spec):
    return f'''# Adapted from Salesforce Agent Script Recipes. See ../../../../../PROVENANCE.json.
config:
    developer_name: "{spec['api']}"
    agent_label: "{spec['label']}"
    agent_type: "{AGENT_TYPE}"
    default_agent_user: "{DEFAULT_AGENT_USER}"
    description: "{spec['purpose']}"

system:
    instructions: "You are {spec['role']}. Use the supplied facts and the configured action. Do not send messages, create bookings, or change records."
    messages:
        welcome: "I can help you prepare a draft. Share the {spec['inputLabel'].lower()} to get started."
        error: "The draft could not be prepared. Please try again."

start_agent agent_router:
    description: "Route requests to the drafting workflow."
    reasoning:
        instructions:|
            Route requests in this assistant's scope to the drafting workflow. Briefly explain the scope for unrelated requests.
        actions:
            begin_work: @utils.transition to @subagent.{spec['topic']}
                description: "{spec['purpose']}"

subagent {spec['topic']}:
    description: "{spec['purpose']}"
    reasoning:
        instructions: ->
            | Ask for the {spec['inputLabel'].lower()} if it is missing. Preserve the supplied text when passing it to the drafting action.
            | Once that input is available, use {{!@actions.{spec['action']}}} and show the returned draft to the user for review.
            | If the user corrects the input or asks for a revision, use the action with the revised input. Do not retry automatically on an error.
        actions:
            {spec['action']}: @actions.{spec['action']}
                with "Input:{spec['input']}" = ...
    actions:
        {spec['action']}:
            description: "{spec['purpose']}"
            inputs:
                "Input:{spec['input']}": string
                    description: "{spec['inputLabel']}, forwarded unchanged from the user's supplied text."
                    is_required: True
            outputs:
                promptResponse: string
                    description: "Draft content for the user to review."
                    is_used_by_planner: True
                    is_displayable: True
            target: "generatePromptResponse://{spec['template']}"
'''

for spec in SPECS:
    prompt(spec['template'], spec['templateLabel'], spec['input'], spec['inputLabel'], spec['content'])
    folder = META / 'aiAuthoringBundles' / spec['api']; folder.mkdir(parents=True, exist_ok=True)
    (folder / (spec['api'] + '.agent')).write_text(simple_agent(spec))

control_api = 'Ohm_Schedule_Desk'
prompt('Ohm_Present_Validated_Plan', 'Present a Validated Day Plan', 'validatedPlan', 'Validated day plan', presentation)
control = '''# Adapted from Salesforce Agent Script Recipes prompt actions and action chaining. See PROVENANCE.json.
config:
    developer_name: "Ohm_Schedule_Desk"
    agent_label: "Efficient Schedule Desk"
    agent_type: "__AGENT_TYPE__"
    default_agent_user: "__DEFAULT_AGENT_USER__"
    description: "Prepare a deterministic day plan in Apex, then present the validated plan to the guest."

variables:
    validated_plan: mutable string = ""
        description: "The schedule preparation result returned by Apex."
    guest_message: mutable string = ""
        description: "The final message returned by the presentation prompt."

system:
    instructions: "You are a guest coordinator at Cedar Bay Retreat. Use the configured schedule preparation and presentation actions. Do not create bookings or change records."
    messages:
        welcome: "Share activity rows as HH:MM|duration minutes|activity name|location, and I will prepare your day plan."
        error: "The plan could not be prepared. Please try again."

start_agent agent_router:
    description: "Route day-planning requests to the schedule desk."
    reasoning:
        instructions:|
            Route guest day-planning requests to the schedule desk. Briefly explain the scope for unrelated requests.
        actions:
            begin_planning: @utils.transition to @subagent.schedule_desk
                description: "Prepare a schedule from activity rows."

subagent schedule_desk:
    description: "Prepare and present a guest day plan from supplied activity rows."
    actions:
        prepare_schedule:
            description: "Use Apex to validate activity rows, sort by time, and select the earliest compatible activities with the minimum gap."
            inputs:
                activities: string
                    description: "Activity rows from the user, forwarded unchanged. Each line is HH:MM|duration minutes|activity name|location."
                    is_required: True
            outputs:
                scheduleText: string
                    description: "The validated schedule or a request to correct invalid input."
                valid: boolean
                    description: "Whether the input rows passed validation."
            target: "apex://OhmDemoScheduleService"
        present_schedule:
            description: "Present the prepared output as one concise guest message while preserving all facts."
            inputs:
                "Input:validatedPlan": string
                    description: "The unmodified schedule preparation result."
                    is_required: True
            outputs:
                promptResponse: string
                    description: "The guest-facing message."
                    is_used_by_planner: True
                    is_displayable: True
            target: "generatePromptResponse://Ohm_Present_Validated_Plan"
    reasoning:
        instructions: ->
            | Ask for activity rows if none are supplied. Forward those rows unchanged to the preparation action; all time calculations and validation belong to that action.
            | Use {!@actions.prepare_schedule} for supplied rows. The configured action chain prepares the schedule and then produces its presentation.
            | Show the returned guest message for review. If the guest corrects the rows, use the action again with those corrections. Do not retry automatically.
            if @variables.guest_message:
                | Prepared guest message: {!@variables.guest_message}
        actions:
            prepare_schedule: @actions.prepare_schedule
                with activities=...
                set @variables.validated_plan = @outputs.scheduleText
                run @actions.present_schedule
                    with "Input:validatedPlan" = @variables.validated_plan
                    set @variables.guest_message = @outputs.promptResponse
'''
control = control.replace('__AGENT_TYPE__', AGENT_TYPE).replace('__DEFAULT_AGENT_USER__', DEFAULT_AGENT_USER)
folder = META / 'aiAuthoringBundles' / control_api; folder.mkdir(parents=True, exist_ok=True)
(folder / (control_api + '.agent')).write_text(control)
for api in [s['api'] for s in SPECS] + [control_api]:
    element = ET.Element(f'{{{NS}}}AiAuthoringBundle'); node(element, 'bundleType', 'AGENT')
    save_xml(META / 'aiAuthoringBundles' / api / (api + '.bundle-meta.xml'), element)

permissions = ET.Element(f'{{{NS}}}PermissionSet')
access = node(permissions, 'classAccesses'); node(access, 'apexClass', 'OhmDemoScheduleService'); node(access, 'enabled', 'true')
node(permissions, 'description', 'Access to the deterministic schedule action in the isolated Ohm event fixtures.')
node(permissions, 'hasActivationRequired', 'false'); node(permissions, 'label', 'Ohm Event Fixture Access')
save_xml(META / 'permissionsets/Ohm_Event_Fixture_Access.permissionset-meta.xml', permissions)
project = {'packageDirectories': [{'path': 'force-app', 'default': True}], 'name': 'ohm-event-fixtures', 'namespace': '', 'sourceApiVersion': '67.0', 'sfdcLoginUrl': 'https://login.salesforce.com'}
(BASE / 'sfdx-project.json').write_text(json.dumps(project, indent=2) + '\n')
shutil.copyfile(UPSTREAM / 'LICENSE.md', BASE / 'LICENSE.md')
upstream_paths = [
 'force-app/main/02_actionConfiguration/promptTemplateActions/aiAuthoringBundles/PromptTemplateActions/PromptTemplateActions.agent',
 'force-app/main/02_actionConfiguration/promptTemplateActions/genAiPromptTemplates/Generate_Personalized_Schedule.genAiPromptTemplate-meta.xml',
 'force-app/main/02_actionConfiguration/actionChaining/aiAuthoringBundles/ActionChaining/ActionChaining.agent',
 'force-app/main/02_actionConfiguration/actionDefinitions/classes/WeatherAlertService.cls'
]
provenance = {
 'kind': 'Controlled test fixtures adapted from public Salesforce recipes; added issues are not upstream defects.',
 'upstreamRepository': 'https://github.com/trailheadapps/agent-script-recipes', 'upstreamCommit': 'ac5ccac8f675153035370abbdce174e2b769c89c', 'license': 'Apache-2.0',
 'upstreamFiles': [{'path': p, 'sha256': sha((UPSTREAM / p).read_bytes())} for p in upstream_paths],
 'changes': ['New fixture agent identities and synthetic support, sales, and retreat scenarios.', 'Reuse public transition, linked prompt, invocable Apex, and run/set action wiring.', 'Published as AgentforceServiceAgent with a dedicated Einstein Agent User (default_agent_user) because the hackathon trial org is not licensed for the Employee Agent template; the upstream recipes use AgentforceEmployeeAgent.', 'Linked prompts run on sfdc_ai__DefaultGPT55 (the newest alias available in the hackathon org) instead of the recipe default sfdc_ai__DefaultOpenAIGPT4OmniMini.', 'Replace the original Salesforce-data provider with required primitive String inputs so there are no custom object or Data Cloud dependencies.', 'Support prompt deliberately repeats policy. Sales prompt deliberately overproduces formats. Schedule prompt explicitly performs bounded scheduling rules.', 'New pure Apex schedule preparation and its tests form the efficient control; its linked prompt only presents the prepared result.'],
 'fixtures': [{k: s[k] for k in ['api', 'label', 'template', 'expected']} for s in SPECS] + [{'api': control_api, 'label': 'Efficient Schedule Desk', 'template': 'Ohm_Present_Validated_Plan', 'expected': 'No CALLS_DETERMINISTIC_ALTERNATIVE for existing Apex/run/set work; A is not preassigned.'}],
 'files': [{'path': str(p.relative_to(BASE)), 'sha256': sha(p.read_bytes())} for p in sorted(META.rglob('*')) if p.is_file()]
}
(BASE / 'PROVENANCE.json').write_text(json.dumps(provenance, indent=2) + '\n')
print(json.dumps({'output': str(BASE), 'bundles': 4, 'linkedPromptTemplates': 4, 'apexClasses': 2, 'metadataFiles': len(provenance['files'])}, indent=2))
