/**
 * OhmSignalDetectorTest — positive / negative / boundary / bulk for all four detectors (T.3.5).
 * Uses the single OhmSeverity.band mapping (C7) and hard-asserts canonical Signal_Type values (C2).
 */
@IsTest
private class OhmSignalDetectorTest {

    // ---------- helpers ----------
    static OhmDTO.ActionNode action(String dev, String label, String descr, String targetType, String model) {
        OhmDTO.ActionNode a = new OhmDTO.ActionNode();
        a.id = 'ACT' + dev;
        a.developerName = dev;
        a.masterLabel = label;
        a.description = descr;
        a.invocationTargetType = targetType;
        a.boundModel = model;
        return a;
    }

    static OhmDTO.AgentModel withActions(List<OhmDTO.ActionNode> acts) {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        g.actions = acts;
        return g;
    }

    static OhmDTO.AgentModel withTopic(String scope) {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.TopicNode t = new OhmDTO.TopicNode();
        t.id = 'TPC1';
        t.developerName = 'Bloated_Topic';
        t.masterLabel = 'Bloated Topic';
        t.scope = scope;
        g.topics = new List<OhmDTO.TopicNode>{ t };
        return g;
    }

    static OhmDTO.AgentModel withAgentGraph(String graphJson) {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.AgentNode a = new OhmDTO.AgentNode();
        a.id = 'AGT1';
        a.developerName = 'Fixture_Bot';
        a.masterLabel = 'Fixture Bot';
        a.agentGraphJson = graphJson;
        g.agentsById.put('AGT1', a);
        return g;
    }

    // ============ (a) LLM_WHERE_DETERMINISTIC ============
    @IsTest
    static void test_a_positive_oneHit() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyLeadPriority', 'Classify Lead Priority', 'Decide the lead priority', 'prompt', null)
        });
        List<OhmDTO.Finding> f = new LlmWhereDeterministicDetector().detect(g);
        System.assertEquals(1, f.size(), 'one finding');
        System.assertEquals('LLM_WHERE_DETERMINISTIC', f[0].signalType, 'canonical C2 value');
        System.assertEquals(0.55, f[0].severityScore, '1 hit -> 0.55');
        System.assertEquals('Medium', f[0].severity);
        System.assertEquals('Medium', f[0].confidence);
    }

    @IsTest
    static void test_a_generatePromptResponse_fires() {
        // API v67 emits 'generatePromptResponse' (not 'prompt') for prompt-backed actions.
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyLeadTier', 'Classify Lead Tier', 'Route the lead into a tier', 'generatePromptResponse', null)
        });
        List<OhmDTO.Finding> f = new LlmWhereDeterministicDetector().detect(g);
        System.assertEquals(1, f.size(), 'generatePromptResponse action must fire signal (a)');
        System.assertEquals('LLM_WHERE_DETERMINISTIC', f[0].signalType);
    }

    @IsTest
    static void test_a_positive_twoHits_high() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyAndRoute', 'Classify and route the case', '', 'prompt', null)
        });
        List<OhmDTO.Finding> f = new LlmWhereDeterministicDetector().detect(g);
        System.assertEquals(1, f.size());
        System.assertEquals(0.70, f[0].severityScore, '2 hits -> 0.70');
        System.assertEquals('High', f[0].severity);
    }

    @IsTest
    static void test_a_negative_apex() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyLeadPriority', 'Classify Lead Priority', '', 'apex', null)
        });
        System.assertEquals(0, new LlmWhereDeterministicDetector().detect(g).size(), 'apex never flagged');
    }

    @IsTest
    static void test_a_negative_noLexicon() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('DraftReply', 'Draft Empathetic Reply', 'Write a warm reply', 'prompt', null)
        });
        System.assertEquals(0, new LlmWhereDeterministicDetector().detect(g).size(), 'no lexicon hit');
    }

    @IsTest
    static void test_a_bulk_noGovernor() {
        List<OhmDTO.ActionNode> acts = new List<OhmDTO.ActionNode>();
        for (Integer i = 0; i < 200; i++) {
            String tt = Math.mod(i, 2) == 0 ? 'prompt' : 'apex';
            acts.add(action('Classify' + i, 'Classify item ' + i, '', tt, null));
        }
        Test.startTest();
        List<OhmDTO.Finding> f = new LlmWhereDeterministicDetector().detect(withActions(acts));
        Test.stopTest();
        System.assertEquals(100, f.size(), 'only the 100 prompt actions fire');
        System.assertEquals(0, Limits.getQueries(), 'no SOQL in detector');
        System.assertEquals(0, Limits.getDmlStatements(), 'no DML in detector');
    }

    @IsTest
    static void test_a_malformed_empty() {
        System.assertEquals(0, new LlmWhereDeterministicDetector().detect(null).size(), 'null graph -> empty');
        System.assertEquals(0, new LlmWhereDeterministicDetector().detect(new OhmDTO.AgentModel()).size());
    }

    // ============ (c) INSTRUCTION_BLOAT ============
    @IsTest
    static void test_c_positive_excessNotTotal() {
        String scope = 'x'.repeat(5200); // 1300 tokens
        List<OhmDTO.Finding> f = new InstructionBloatDetector().detect(withTopic(scope));
        System.assertEquals(1, f.size());
        System.assertEquals('INSTRUCTION_BLOAT', f[0].signalType, 'canonical C2 value');
        System.assertEquals(800, f[0].metricValue, 'C9 EXCESS = 1300-500 = 800');
        System.assertEquals('tokens', f[0].metricUnit);
        System.assertEquals(1.0, f[0].severityScore, 'min(1,800/500)=1.0');
        System.assertEquals('High', f[0].severity);
        System.assertEquals('High', f[0].confidence);
    }

    @IsTest
    static void test_c_boundary_exactlySoft_noFire() {
        String scope = 'x'.repeat(2000); // exactly 500 tokens
        System.assertEquals(0, new InstructionBloatDetector().detect(withTopic(scope)).size(), '== soft -> no fire (strict >)');
    }

    @IsTest
    static void test_c_boundary_softPlusOne_fires() {
        String scope = 'x'.repeat(2004); // 501 tokens
        List<OhmDTO.Finding> f = new InstructionBloatDetector().detect(withTopic(scope));
        System.assertEquals(1, f.size(), '501 tokens -> fires');
        System.assertEquals(1, f[0].metricValue, 'excess 1');
    }

    @IsTest
    static void test_c_negative_short() {
        String scope = 'x'.repeat(200); // 50 tokens
        System.assertEquals(0, new InstructionBloatDetector().detect(withTopic(scope)).size());
    }

    @IsTest
    static void test_c_agentThreshold() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        OhmDTO.AgentNode a = new OhmDTO.AgentNode();
        a.id = 'AG'; a.developerName = 'Verbose_Agent';
        a.description = 'y'.repeat(2000); // 500 tokens > agent soft 400
        g.agentsById.put('AG', a);
        List<OhmDTO.Finding> f = new InstructionBloatDetector().detect(g);
        System.assertEquals(1, f.size(), 'agent soft 400 exceeded');
        System.assertEquals('Agent', f[0].artifactType);
        System.assertEquals(100, f[0].metricValue, 'excess 500-400=100');
    }

    @IsTest
    static void test_c_bulk() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        g.topics = new List<OhmDTO.TopicNode>();
        for (Integer i = 0; i < 200; i++) {
            OhmDTO.TopicNode t = new OhmDTO.TopicNode();
            t.id = 'T' + i; t.developerName = 'T' + i;
            t.scope = 'x'.repeat(5200);
            g.topics.add(t);
        }
        Test.startTest();
        List<OhmDTO.Finding> f = new InstructionBloatDetector().detect(g);
        Test.stopTest();
        System.assertEquals(200, f.size());
        System.assertEquals(0, Limits.getQueries(), 'no per-record SOQL');
    }

    // ============ (b) MODEL_RIGHTSIZING ============
    @IsTest
    static void test_b_positive_largeOnTrivial() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyPriority', 'Classify priority', 'route into High/Medium/Low', 'prompt', 'LARGE')
        });
        List<OhmDTO.Finding> f = new ModelRightSizingDetector().detect(g);
        System.assertEquals(1, f.size());
        System.assertEquals('MODEL_RIGHTSIZING', f[0].signalType, 'canonical C2 value');
        System.assertEquals(1.0, f[0].severityScore, 'overshoot 2 -> min(1,1.0)=1.0');
        System.assertEquals('High', f[0].severity);
        System.assertEquals('Medium', f[0].confidence);
        System.assertEquals(2.0, f[0].metricValue, 'bound multiplier 2.0');
        System.assertEquals('SMALL', f[0].recommendedTarget);
    }

    @IsTest
    static void test_b_boundary_overshootOne() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyPriority', 'Classify priority', '', 'prompt', 'MEDIUM')
        });
        List<OhmDTO.Finding> f = new ModelRightSizingDetector().detect(g);
        System.assertEquals(1, f.size());
        System.assertEquals(0.5, f[0].severityScore, 'overshoot 1 -> 0.5');
        System.assertEquals('Medium', f[0].severity);
    }

    @IsTest
    static void test_b_degrade_nullModel() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyPriority', 'Classify priority', '', 'prompt', null)
        });
        List<OhmDTO.Finding> f = new ModelRightSizingDetector().detect(g);
        System.assertEquals(1, f.size(), 'informational finding');
        System.assertEquals('model unknown', f[0].evidence);
        System.assertEquals('Low', f[0].confidence);
        System.assertEquals('Low', f[0].severity, 'score 0 -> Low');
    }

    @IsTest
    static void test_b_negative_rightSized() {
        OhmDTO.AgentModel g = withActions(new List<OhmDTO.ActionNode>{
            action('ClassifyPriority', 'Classify priority', '', 'prompt', 'SMALL')
        });
        System.assertEquals(0, new ModelRightSizingDetector().detect(g).size(), 'SMALL on trivial -> right-sized');
    }

    @IsTest
    static void test_b_neverCallout_bulk() {
        List<OhmDTO.ActionNode> acts = new List<OhmDTO.ActionNode>();
        for (Integer i = 0; i < 200; i++) {
            acts.add(action('Classify' + i, 'Classify item ' + i, '', 'prompt', 'LARGE'));
        }
        Test.startTest();
        List<OhmDTO.Finding> f = new ModelRightSizingDetector().detect(withActions(acts));
        Test.stopTest();
        System.assertEquals(200, f.size());
        System.assertEquals(0, Limits.getCallouts(), 'detector never performs a callout');
    }

    // ============ (d) REDUNDANT_CALLS ============
    static String fixtureGraph() {
        return '{ "nodes":[' +
            '{"id":"n1","type":"action","ref":"Ohm_Fixture_ClassifyPriority","invocationTargetType":"prompt"},' +
            '{"id":"n2","type":"action","ref":"Ohm_Fixture_SummarizeLead","invocationTargetType":"prompt"},' +
            '{"id":"n3","type":"action","ref":"Ohm_Fixture_ClassifyPriority","invocationTargetType":"prompt"} ],' +
            '"edges":[{"from":"n1","to":"n2"},{"from":"n2","to":"n3"}],' +
            '"turns":[{"turn":1,"calls":["n1","n2","n3"]}] }';
    }

    @IsTest
    static void test_d_positive_fixture() {
        List<OhmDTO.Finding> f = new RedundantCallDetector().detect(withAgentGraph(fixtureGraph()));
        System.assertEquals(1, f.size());
        System.assertEquals('REDUNDANT_CALLS', f[0].signalType, 'canonical C2 value');
        System.assertEquals(2, f[0].metricValue, 'extraCalls = 3-1 = 2');
        System.assertEquals('calls-per-turn', f[0].metricUnit);
        System.assertEquals(0.67, f[0].severityScore, '0.34 + 0.165*2 = 0.67');
        System.assertEquals('High', f[0].severity);
        System.assertEquals('Low', f[0].confidence);
        System.assert(f[0].evidence.toLowerCase().contains('duplicate'), 'notes duplicate target');
    }

    @IsTest
    static void test_d_positive_cycle() {
        String cyclic = '{ "nodes":[' +
            '{"id":"a","invocationTargetType":"prompt"},' +
            '{"id":"b","invocationTargetType":"prompt"}],' +
            '"edges":[{"from":"a","to":"b"},{"from":"b","to":"a"}],' +
            '"turns":[{"turn":1,"calls":["a","b"]}] }';
        List<OhmDTO.Finding> f = new RedundantCallDetector().detect(withAgentGraph(cyclic));
        System.assertEquals(1, f.size());
        System.assertEquals(1.0, f[0].severityScore, 'cycle forces 1.0');
        System.assertEquals('High', f[0].severity);
        System.assert(f[0].evidence.contains('×N'), 'cycle caveat present');
    }

    @IsTest
    static void test_d_negative_single() {
        String single = '{ "nodes":[{"id":"n1","invocationTargetType":"prompt"}],' +
            '"edges":[],"turns":[{"turn":1,"calls":["n1"]}] }';
        System.assertEquals(0, new RedundantCallDetector().detect(withAgentGraph(single)).size(), 'single prompt node -> 0');
    }

    @IsTest
    static void test_d_degrade_malformed() {
        OhmDTO.AgentModel g = withAgentGraph('{ not valid json');
        List<OhmDTO.Finding> f = new RedundantCallDetector().detect(g);
        System.assertEquals(0, f.size(), 'malformed -> no finding');
        System.assert(!g.discoveryErrors.isEmpty(), 'discovery error appended');
    }

    @IsTest
    static void test_d_unknownKeys_ignored() {
        String weird = '{ "foo":"bar","nodes":[' +
            '{"id":"n1","invocationTargetType":"prompt","surprise":true},' +
            '{"id":"n2","invocationTargetType":"prompt"}],' +
            '"turns":[{"turn":1,"calls":["n1","n2"]}] }';
        List<OhmDTO.Finding> f = new RedundantCallDetector().detect(withAgentGraph(weird));
        System.assertEquals(1, f.size(), 'unknown keys ignored, still fires on 2 prompt calls');
        System.assertEquals(1, f[0].metricValue, 'extraCalls 1');
    }

    @IsTest
    static void test_d_emptyGraph_noThrow() {
        System.assertEquals(0, new RedundantCallDetector().detect(withAgentGraph('')).size());
        System.assertEquals(0, new RedundantCallDetector().detect(new OhmDTO.AgentModel()).size());
    }
}
