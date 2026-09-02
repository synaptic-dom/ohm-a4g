/**
 * OhmFootprintServiceTest — band math pinned to §6.2 constants + single-path savings (T.3.7).
 */
@IsTest
private class OhmFootprintServiceTest {

    static OhmDTO.FootprintRequest req(Decimal tokens, Decimal calls, String model) {
        OhmDTO.FootprintRequest r = new OhmDTO.FootprintRequest();
        r.tokensPerInference = tokens;
        r.annualCalls = calls;
        r.boundModel = model;
        return r;
    }

    static OhmDTO.Finding finding(String signal, String artifactType, Decimal metric, String recTarget) {
        OhmDTO.Finding f = new OhmDTO.Finding();
        f.signalType = signal;
        f.artifactType = artifactType;
        f.metricValue = metric;
        f.recommendedTarget = recTarget;
        return f;
    }

    @IsTest
    static void test_estimate_centralPin() {
        // annualCalls=10000, multiplier 1.0, tokens=reference(500)
        OhmDTO.FootprintResponse r = new OhmFootprintService().estimate(req(500, 10000, null));
        System.assertEquals(2700, r.energyWhCentral, 'energy 0.27×10000');
        System.assertEquals(810, r.co2eGCentral, 'co2e 2700×0.30');
        System.assertEquals(2916, r.waterMlCentral, 'water 2700×1.08');
        // low band
        System.assertEquals(2400, r.energyWhLow, '0.24×10000');
        System.assertEquals(300, r.co2eGLow, '2400×0.125');
        System.assertEquals(1920, r.waterMlLow, '2400×0.8');
        // high band
        System.assertEquals(3000, r.energyWhHigh, '0.30×10000');
        System.assertEquals(1425, r.co2eGHigh, '3000×0.475');
        System.assertEquals(4200, r.waterMlHigh, '3000×1.4');
        System.assertEquals(false, r.telemetryBacked);
        System.assertEquals('Low', r.confidence);
    }

    @IsTest
    static void test_bandOrdering() {
        OhmDTO.FootprintResponse r = new OhmFootprintService().estimate(req(500, 10000, null));
        System.assert(r.energyWhLow <= r.energyWhCentral && r.energyWhCentral <= r.energyWhHigh, 'energy ordered');
        System.assert(r.co2eGLow <= r.co2eGCentral && r.co2eGCentral <= r.co2eGHigh, 'co2e ordered');
        System.assert(r.waterMlLow <= r.waterMlCentral && r.waterMlCentral <= r.waterMlHigh, 'water ordered');
    }

    @IsTest
    static void test_tokenAndMultiplierScaling() {
        OhmFootprintService svc = new OhmFootprintService();
        OhmDTO.FootprintResponse base = svc.estimate(req(500, 10000, null));
        OhmDTO.FootprintResponse dblTok = svc.estimate(req(1000, 10000, null));
        System.assertEquals(base.energyWhCentral * 2, dblTok.energyWhCentral, 'token 2x -> energy 2x');
        OhmDTO.FootprintResponse dblMult = svc.estimate(req(500, 10000, 'LARGE'));
        System.assertEquals(base.energyWhCentral * 2, dblMult.energyWhCentral, 'multiplier 2.0 -> energy 2x');
    }

    @IsTest
    static void test_unknownModel_assumed() {
        OhmDTO.FootprintResponse r = new OhmFootprintService().estimate(req(500, 10000, 'mystery-model'));
        System.assertEquals(2700, r.energyWhCentral, 'unknown -> baseline 1.0');
        System.assertEquals(true, r.assumptions.get('modelAssumed'), 'modelAssumed disclosed');
    }

    @IsTest
    static void test_zeroCalls_noDivideByZero() {
        OhmDTO.FootprintResponse r = new OhmFootprintService().estimate(req(500, 0, null));
        System.assertEquals(0, r.energyWhCentral);
        System.assertEquals(0, r.co2eGCentral);
        System.assertEquals(0, r.waterMlCentral);
    }

    @IsTest
    static void test_assumptions_disclosed() {
        OhmDTO.FootprintResponse r = new OhmFootprintService().estimate(req(500, 10000, null));
        System.assert(r.assumptions.containsKey('energyPerPromptWh'), 'discloses energy constant');
        System.assert(r.assumptions.containsKey('gridIntensityGco2ePerWh'), 'discloses grid');
        System.assert(r.assumptions.containsKey('waterMlPerWh'), 'discloses water');
        System.assertEquals(false, r.assumptions.get('telemetryBacked'), 'telemetry disclosed false');
    }

    @IsTest
    static void test_C3_vocabulary() {
        String js = JSON.serialize(new OhmFootprintService().estimate(req(500, 10000, null)));
        System.assert(js.contains('energyWhCentral'), 'central key');
        System.assert(!js.contains('mid'), 'no mid');
        System.assert(!js.contains('"point'), 'no point key');
    }

    // ---------- savings single-path (defaultVolume = 109500) ----------
    static OhmDTO.VolumeInput vol() {
        return new AssumptionVolumeProvider().defaultVolume();
    }

    @IsTest
    static void test_savings_a_fullBaseline() {
        OhmDTO.Finding f = finding('LLM_WHERE_DETERMINISTIC', 'Action', 1, null);
        OhmDTO.FootprintResponse s = new OhmFootprintService().savingsFor(f, vol());
        // full baseline: 0.27 × 109500 = 29565
        System.assertEquals(29565, s.energyWhCentral, '(a) removed call = full baseline');
    }

    @IsTest
    static void test_savings_b_multiplierRatio() {
        // bound LARGE (2.0), recommend SMALL (0.5); savings = baseline1x × (2.0−0.5)
        OhmDTO.Finding f = finding('MODEL_RIGHTSIZING', 'Action', 2.0, 'SMALL');
        OhmFootprintService svc = new OhmFootprintService();
        OhmDTO.FootprintResponse s = svc.savingsFor(f, vol());
        System.assertEquals(44347.5, s.energyWhCentral, '(b) 29565 × 1.5');
        // footprint (at bound multiplier) = 29565 × 2.0 = 59130 ; savings/footprint = 1 − mRec/mBound = 0.75
        OhmDTO.FootprintResponse fp = svc.estimateForArtifact(f, vol());
        System.assertEquals(59130, fp.energyWhCentral, 'footprint at bound multiplier');
        System.assertEquals(0.75, (s.energyWhCentral / fp.energyWhCentral).setScale(2), 'ratio 1−m2/m1');
    }

    @IsTest
    static void test_savings_c_tokenDelta() {
        // Topic excess 800, soft 500 -> total 1300 ; savings = baseline(1300) − baseline(500)
        OhmDTO.Finding f = finding('INSTRUCTION_BLOAT', 'Topic', 800, null);
        OhmDTO.FootprintResponse s = new OhmFootprintService().savingsFor(f, vol());
        // baseline central 0.27×(1300/500)×109500 = 76869 ; fixed 0.27×109500 = 29565 ; savings = 47304
        System.assertEquals(47304, s.energyWhCentral, '(c) token-delta savings');
    }

    @IsTest
    static void test_savings_d_callDelta() {
        // extraCalls 2 -> baseline callsPerTurn 3, fixed callsPerTurn 1
        OhmDTO.Finding f = finding('REDUNDANT_CALLS', 'Agent', 2, null);
        OhmDTO.FootprintResponse s = new OhmFootprintService().savingsFor(f, vol());
        // baseline 0.27×328500 = 88695 ; fixed 0.27×109500 = 29565 ; savings = 59130
        System.assertEquals(59130, s.energyWhCentral, '(d) call-delta savings');
    }

    @IsTest
    static void test_sumAll_orgWide() {
        OhmFootprintService svc = new OhmFootprintService();
        OhmDTO.FootprintResponse a = svc.estimate(req(500, 10000, null));
        OhmDTO.FootprintResponse b = svc.estimate(req(500, 10000, null));
        OhmDTO.FootprintResponse total = svc.sumAll(new List<OhmDTO.FootprintResponse>{ a, b });
        System.assertEquals(5400, total.energyWhCentral, 'sumAll adds bands element-wise');
        System.assertEquals(20000, total.annualCalls, 'calls summed');
    }
}
