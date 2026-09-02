/**
 * OhmSignalServiceTest — analyze() orchestration + rate() grade math (T.3.6, canon C8).
 */
@IsTest
private class OhmSignalServiceTest {

    static OhmDTO.ActionNode action(String dev, String label, String tt, String model) {
        OhmDTO.ActionNode a = new OhmDTO.ActionNode();
        a.id = 'A' + dev; a.developerName = dev; a.masterLabel = label;
        a.invocationTargetType = tt; a.boundModel = model;
        return a;
    }

    static OhmDTO.Finding finding(String signal, Decimal score) {
        OhmDTO.Finding f = new OhmDTO.Finding();
        f.signalType = signal; f.severityScore = score; f.severity = OhmSeverity.band(score);
        return f;
    }

    @IsTest
    static void test_rate_cleanModel_gradeA() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        g.actions = new List<OhmDTO.ActionNode>{
            action('LookupCredit', 'Lookup credit via Apex', 'apex', null),
            action('CreateCase', 'Create case', 'flow', null)
        };
        OhmSignalService svc = new OhmSignalService();
        List<OhmDTO.Finding> findings = svc.analyze(g);
        System.assertEquals(0, findings.size(), 'clean all-apex/flow model -> no findings');
        OhmDTO.EfficiencyResult r = svc.rate(g, findings);
        System.assertEquals(100, r.score, 'no findings -> 100');
        System.assertEquals('A', r.grade, 'clean -> A (NFR-4 dogfood)');
        System.assertEquals(2, r.deterministicActionCount, 'apex+flow counted');
    }

    @IsTest
    static void test_rate_mixedFindings_formula() {
        // F = round(100 × (1 − Σ(weight×score)/Σweight))
        // LLM_WHERE_DETERMINISTIC w1.0 s0.55 ; INSTRUCTION_BLOAT w0.5 s1.0
        // weightedSum = 0.55 + 0.5 = 1.05 ; maxPossible = 1.5 ; score = round(100×(1−0.7)) = 30 -> F
        List<OhmDTO.Finding> findings = new List<OhmDTO.Finding>{
            finding('LLM_WHERE_DETERMINISTIC', 0.55),
            finding('INSTRUCTION_BLOAT', 1.0)
        };
        OhmDTO.EfficiencyResult r = new OhmSignalService().rate(new OhmDTO.AgentModel(), findings);
        System.assertEquals(1.05, r.weightedSeveritySum, 'weighted sum');
        System.assertEquals(1.5, r.maxPossible, 'max possible');
        System.assertEquals(30, r.score, 'grade math');
        System.assertEquals('F', r.grade);
    }

    @IsTest
    static void test_analyze_fourSignalFixture_lowGrade() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        // (a)+(b): prompt action, deterministic label, oversized model
        g.actions = new List<OhmDTO.ActionNode>{
            action('ClassifyPriority', 'Classify and route priority into High/Medium/Low', 'prompt', 'LARGE')
        };
        // (c): bloated topic
        OhmDTO.TopicNode t = new OhmDTO.TopicNode();
        t.id = 'TPC'; t.developerName = 'LeadTriage'; t.scope = 'x'.repeat(5200);
        g.topics = new List<OhmDTO.TopicNode>{ t };
        // (d): redundant agent graph
        OhmDTO.AgentNode ag = new OhmDTO.AgentNode();
        ag.id = 'AGT'; ag.developerName = 'LeadBot';
        ag.agentGraphJson = '{ "nodes":[' +
            '{"id":"n1","invocationTargetType":"prompt","ref":"ClassifyPriority"},' +
            '{"id":"n2","invocationTargetType":"prompt","ref":"SummarizeLead"},' +
            '{"id":"n3","invocationTargetType":"prompt","ref":"ClassifyPriority"}],' +
            '"turns":[{"turn":1,"calls":["n1","n2","n3"]}] }';
        g.agentsById.put('AGT', ag);

        OhmSignalService svc = new OhmSignalService();
        List<OhmDTO.Finding> findings = svc.analyze(g);
        System.assert(findings.size() >= 4, 'trips all four signals: ' + findings.size());

        Set<String> signals = new Set<String>();
        for (OhmDTO.Finding f : findings) { signals.add(f.signalType); }
        System.assert(signals.contains('LLM_WHERE_DETERMINISTIC'), 'a present');
        System.assert(signals.contains('MODEL_RIGHTSIZING'), 'b present');
        System.assert(signals.contains('INSTRUCTION_BLOAT'), 'c present');
        System.assert(signals.contains('REDUNDANT_CALLS'), 'd present');

        OhmDTO.EfficiencyResult r = svc.rate(g, findings);
        System.assert(r.score < 60, 'wasteful org grades low, score=' + r.score);
        System.assertEquals('F', r.grade, 'four-signal fixture -> F');
    }

    @IsTest
    static void test_analyze_empty_noException() {
        OhmSignalService svc = new OhmSignalService();
        System.assertEquals(0, svc.analyze(null).size(), 'null -> empty');
        System.assertEquals(0, svc.analyze(new OhmDTO.AgentModel()).size(), 'empty graph -> empty');
    }
}
