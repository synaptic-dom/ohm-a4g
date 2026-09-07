@IsTest
private class OhmSourceParserTest {
    private static final String NS = 'http://soap.sforce.com/2006/04/metadata';
    private static String script() {
        return 'config:\n   developer_name: "Weather"\n'
            + 'system:\n   instructions: "Keep the user safe."\n'
            + 'start_agent router:\n   reasoning:\n      instructions:|\n         Choose weather.\n'
            + 'subagent weather:\n   reasoning:\n      instructions:->\n'
            + '         | Check conditions.\n\n         if @variables.location:\n'
            + '            | Use {!@variables.location}.\n         else:\n'
            + '            | Ask for a location.\n\n      actions:\n         get_weather: @actions.lookup\n';
    }
    private static String descriptor(String target) {
        return '<AiAuthoringBundle xmlns="' + NS + '"><bundleType>AGENT</bundleType><target>'
            + target + '</target></AiAuthoringBundle>';
    }
    private static String prompt(String versionBodies, String active) {
        return '<GenAiPromptTemplate xmlns="' + NS + '"><developerName>Schedule</developerName>'
            + '<activeVersionIdentifier>' + active + '</activeVersionIdentifier>' + versionBodies + '</GenAiPromptTemplate>';
    }
    private static String version(String id, String content, String status) {
        return '<templateVersions><content>' + content.escapeXml() + '</content><primaryModel>small-model</primaryModel>'
            + '<status>' + status + '</status><versionIdentifier>' + id + '</versionIdentifier></templateVersions>';
    }

    @IsTest static void keepsConditionalDslAndDedentsOnlyBlockMargin() {
        OhmSourceParser.AgentScript parsed = OhmSourceParser.agentScript(script(), 'Weather');
        System.assertEquals('Keep the user safe.', parsed.systemInstructions);
        System.assertEquals('Choose weather.', parsed.topics.get('router'));
        System.assertEquals('| Check conditions.\n\nif @variables.location:\n   | Use {!@variables.location}.\nelse:\n   | Ask for a location.', parsed.topics.get('weather'));
        System.assertEquals(2, parsed.topics.size());
        System.assertEquals(parsed.topics, OhmSourceParser.agentScript(script().replace('\n', '\r\n'), 'Weather').topics);
    }
    @IsTest static void quotedInstructionsRetainEscapesAndSingleQuotes() {
        String source = 'config:\n  developer_name: "Weather"\n'
            + 'system:\n  instructions: "First\\nSecond"\n'
            + 'start_agent router:\n  reasoning:\n    instructions: \'Don\'\'t send.\'\n';
        OhmSourceParser.AgentScript parsed = OhmSourceParser.agentScript(source, 'Weather');
        System.assertEquals('First\nSecond', parsed.systemInstructions);
        System.assertEquals('Don\'t send.', parsed.topics.get('router'));
    }
    @IsTest static void rejectsWrongScriptIdentityAndUnsupportedExpressions() {
        try { OhmSourceParser.agentScript(script(), 'Different'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('developer_name')); }
        try { OhmSourceParser.agentScript(script().replace('instructions:->', 'instructions: @opaque.external'), 'Weather'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('Unsupported instruction expression')); }
        try { OhmSourceParser.agentScript(script().replace('      instructions:|\n         Choose weather.', '      description: "description is not instructions"'), 'Weather'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('No instruction source')); }
    }
    @IsTest static void targetBindingControlsSelectionRegardlessOfDirectoryCounter() {
        Map<String, String> files = new Map<String, String>{
            'unpackaged/aiAuthoringBundles/Weather/Weather.bundle-meta.xml' => descriptor('Weather.v1'),
            'unpackaged/aiAuthoringBundles/Weather/Weather.agent' => script(),
            'unpackaged/aiAuthoringBundles/Draft/Draft.bundle-meta.xml' => descriptor('Weather.v2'),
            'unpackaged/aiAuthoringBundles/Draft/Draft.agent' => 'draft source'
        };
        OhmSourceParser.PublishedScript selected = OhmSourceParser.publishedScript(files, 'Weather.v1');
        System.assertEquals(script(), selected.script);
        System.assertEquals(null, OhmSourceParser.publishedScript(files, 'Weather.v3'));
        files.remove('unpackaged/aiAuthoringBundles/Weather/Weather.agent');
        try { OhmSourceParser.publishedScript(files, 'Weather.v1'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('no matching Agent Script')); }
    }
    @IsTest static void rejectsAmbiguousPublishedBindings() {
        Map<String, String> files = new Map<String, String>();
        for (String directory : new List<String>{'One', 'Two'}) {
            files.put('aiAuthoringBundles/' + directory + '/' + directory + '.bundle-meta.xml', descriptor('Weather.v1'));
            files.put('aiAuthoringBundles/' + directory + '/' + directory + '.agent', script());
        }
        try { OhmSourceParser.publishedScript(files, 'Weather.v1'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('Multiple')); }
    }
    @IsTest static void selectsOneActivePromptAndPreservesExactText() {
        String exact = '  Preserve  spaces\nline two\nDon\'t collapse\u00a0space & <tokens>.\n';
        String source = prompt(version('older_1', 'inactive text', 'Published') + version('active_7', exact, 'Published'), 'active_7');
        OhmSourceParser.PromptTemplate parsed = OhmSourceParser.promptTemplate(source, 'Schedule');
        System.assertEquals(exact, parsed.instructions);
        System.assertEquals('active_7', parsed.versionIdentifier);
        System.assertEquals('small-model', parsed.boundModel);
        System.assertEquals(OhmSourceImportService.sha256(exact), OhmSourceImportService.sha256(parsed.instructions));
    }
    @IsTest static void refusesMissingDuplicateAndDraftPromptVersions() {
        List<String> invalid = new List<String>{
            prompt(version('v1', 'text', 'Published'), 'v2'),
            prompt(version('v1', 'one', 'Published') + version('v1', 'two', 'Published'), 'v1'),
            prompt(version('v1', 'text', 'Draft'), 'v1'),
            prompt(version('v1', 'text', 'Published'), '')
        };
        for (String source : invalid) {
            Boolean failed = false;
            try { OhmSourceParser.promptTemplate(source, 'Schedule'); }
            catch (OhmSourceParser.SourceParseException ex) { failed = true; }
            System.assert(failed, 'Unresolved active prompt must never use an arbitrary version');
        }
    }
    @IsTest static void legacyUsesNestedInstructionsNeverTopicDescription() {
        String source = '<GenAiPlugin xmlns="' + NS + '"><developerName>Weather</developerName><description>Ignore this summary.</description>'
            + '<genAiPluginInstructions><description>Get location.</description></genAiPluginInstructions>'
            + '<genAiPluginInstructions><description>Check weather.</description></genAiPluginInstructions></GenAiPlugin>';
        System.assertEquals('Get location.\n\nCheck weather.', OhmSourceParser.legacyPlugin(source, 'Weather').instructions);
        try { OhmSourceParser.legacyPlugin(source.replace('Check weather.', ''), 'Weather'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('empty')); }
    }
    @IsTest static void zipReadsActualEntriesWithoutFileProperties() {
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('unpackaged/aiAuthoringBundles/Weather/Weather.agent', Blob.valueOf(script()));
        writer.addEntry('unpackaged/aiAuthoringBundles/Weather/Weather.bundle-meta.xml', Blob.valueOf(descriptor('Weather.v1')));
        writer.addEntry('unpackaged/package.xml', Blob.valueOf('<Package/>'));
        Map<String, String> files = OhmSourceParser.readArchive(writer.getArchive());
        System.assertEquals(2, files.size());
        System.assertEquals(script(), OhmSourceParser.publishedScript(files, 'Weather.v1').script);
    }
    @IsTest static void refusesOversizedAndUnsafeZipEntriesBeforeReturningSources() {
        String huge = 'x'.repeat(OhmSourceParser.MAX_ENTRY_BYTES + 1);
        Compression.ZipWriter writer = new Compression.ZipWriter();
        writer.addEntry('aiAuthoringBundles/Weather/Weather.agent', Blob.valueOf(huge));
        try { OhmSourceParser.readArchive(writer.getArchive()); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('256 KiB')); }
        writer = new Compression.ZipWriter();
        writer.addEntry('../aiAuthoringBundles/Weather/Weather.agent', Blob.valueOf('text'));
        try { OhmSourceParser.readArchive(writer.getArchive()); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('path')); }
    }
    @IsTest static void rejectsUnexpectedNamespaceAndOversizedSource() {
        try { OhmSourceParser.promptTemplate('<GenAiPromptTemplate/>', 'Schedule'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('root')); }
        try { OhmSourceParser.agentScript('x'.repeat(OhmSourceParser.MAX_SOURCE_CHARS + 1), 'Weather'); System.assert(false); }
        catch (OhmSourceParser.SourceParseException ex) { System.assert(ex.getMessage().contains('limit')); }
    }
}
