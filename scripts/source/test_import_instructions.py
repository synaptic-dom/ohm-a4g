"""Parser contracts: preserve source semantics, select exact versions, reject guesses."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).with_name('import-instructions.py')
spec = importlib.util.spec_from_file_location('ohm_source_importer', MODULE_PATH)
importer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(importer)
ROOT = Path(__file__).resolve().parents[2]
RECIPES = ROOT/'test-fixtures/public-agents/agent-script-recipes/force-app/main/02_actionConfiguration'

class SourceParserTests(unittest.TestCase):
    def test_dynamic_weather_preserves_branches_and_action_references(self):
        path = RECIPES/'actionDefinitions/aiAuthoringBundles/actionDefinitions/actionDefinitions.agent'
        system,topics = importer.agent_script(path)
        self.assertIn('helpful weather assistant',system)
        self.assertEqual({'agent_router','weather_lookup'},set(topics))
        self.assertIn('if @variables.location:',topics['weather_lookup'])
        self.assertIn('else:',topics['weather_lookup'])
        self.assertIn('{!@actions.get_current_weather}',topics['weather_lookup'])
        self.assertNotIn('target: "flow://',topics['weather_lookup'])

    def test_payment_reasoning_keeps_sequence(self):
        path = RECIPES/'actionChaining/aiAuthoringBundles/actionChaining/actionChaining.agent'
        _,topics = importer.agent_script(path)
        self.assertEqual(2,len(topics))
        self.assertTrue(all(isinstance(value,str) for value in topics.values()))

    def test_active_prompt_version_and_model(self):
        path = RECIPES/'promptTemplateActions/genAiPromptTemplates/Generate_Personalized_Schedule.genAiPromptTemplate-meta.xml'
        name,content,model,version = importer.prompt_template(path)
        self.assertEqual('Generate_Personalized_Schedule',name)
        self.assertIn('60 minutes',content)
        self.assertEqual('sfdc_ai__DefaultOpenAIGPT4OmniMini',model)
        self.assertTrue(version.endswith('_1'))

    def test_legacy_nested_instructions_are_distinct_from_scope(self):
        path = ROOT/'test-fixtures/public-agents/coral-cloud/cc-employee-app/main/default/genAiPlugins/Customer_Service_Assistant.genAiPlugin-meta.xml'
        name,text = importer.legacy_plugin(path)
        self.assertEqual('Customer_Service_Assistant',name)
        self.assertIn('Do not display or request record IDs',text)
        self.assertIn('Bulk Issue Credit',text)
        self.assertNotIn('Your role is to assist',text)

    def test_unknown_expression_is_rejected(self):
        with self.assertRaisesRegex(ValueError,'Unsupported instruction expression'):
            importer.instructions_in_block('   instructions: @unsupported.variable')

    def test_missing_active_version_is_rejected(self):
        xml = '<GenAiPromptTemplate xmlns="http://soap.sforce.com/2006/04/metadata"><developerName>Unbound</developerName><templateVersions><content>Draft</content></templateVersions></GenAiPromptTemplate>'
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'Unbound.xml'; path.write_text(xml)
            with self.assertRaisesRegex(ValueError,'one active prompt version'):
                importer.prompt_template(path)

if __name__ == '__main__': unittest.main()
