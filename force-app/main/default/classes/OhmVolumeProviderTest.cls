@IsTest
private class OhmVolumeProviderTest {
    @IsTest
    static void test_defaultVolume_and_annualCalls() {
        VolumeProvider vp = new AssumptionVolumeProvider();
        OhmDTO.VolumeInput v = vp.defaultVolume();
        System.assertEquals(50, v.sessionsPerPeriod);
        System.assertEquals(6, v.turnsPerSession);
        System.assertEquals(1, v.callsPerTurn);
        System.assertEquals(365, v.periodsPerYear);
        // canon C6: 50 × 6 × 1 × 365 = 109,500
        System.assertEquals(109500, vp.annualCalls(v), 'default annual calls 109500');
        System.assertEquals(false, vp.isTelemetryBacked(), 'modeled volume not telemetry-backed');
    }

    @IsTest
    static void test_scrubberLinearity() {
        VolumeProvider vp = new AssumptionVolumeProvider();
        OhmDTO.VolumeInput v = vp.defaultVolume();
        Decimal base = vp.annualCalls(v);
        v.sessionsPerPeriod = v.sessionsPerPeriod * 2;
        System.assertEquals(base * 2, vp.annualCalls(v), 'doubling sessions doubles calls');
    }

    @IsTest
    static void test_withCallsPerTurn() {
        VolumeProvider vp = new AssumptionVolumeProvider();
        OhmDTO.VolumeInput base = vp.defaultVolume();
        OhmDTO.VolumeInput v3 = vp.withCallsPerTurn(base, 3);
        System.assertEquals(3, v3.callsPerTurn);
        System.assertEquals(109500 * 3, vp.annualCalls(v3), 'callsPerTurn 3 -> 3x');
    }
}
