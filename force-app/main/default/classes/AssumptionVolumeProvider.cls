/**
 * AssumptionVolumeProvider — modeled (non-telemetry) volume from Ohm_Constants.volumeScenario.
 * Canon C6: annualCalls = sessionsPerPeriod × turnsPerSession × callsPerTurn × periodsPerYear.
 * Demo baseline = 50 × 6 × 1 × 365 = 109,500 calls/yr. telemetryBacked = false.
 */
public with sharing class AssumptionVolumeProvider implements VolumeProvider {

    public OhmDTO.VolumeInput defaultVolume() {
        return OhmConstants.load().defaultVolume();
    }

    public OhmDTO.VolumeInput withCallsPerTurn(OhmDTO.VolumeInput base, Decimal callsPerTurn) {
        OhmDTO.VolumeInput src = (base == null) ? defaultVolume() : base;
        OhmDTO.VolumeInput v = new OhmDTO.VolumeInput();
        v.sessionsPerPeriod = src.sessionsPerPeriod;
        v.turnsPerSession = src.turnsPerSession;
        v.callsPerTurn = callsPerTurn;
        v.periodsPerYear = src.periodsPerYear;
        v.scenarioLabel = src.scenarioLabel;
        return v;
    }

    public Decimal annualCalls(OhmDTO.VolumeInput v) {
        if (v == null) {
            return 0;
        }
        Decimal s = nz(v.sessionsPerPeriod);
        Decimal t = nz(v.turnsPerSession);
        Decimal c = nz(v.callsPerTurn);
        Decimal p = nz(v.periodsPerYear);
        return s * t * c * p;
    }

    public Boolean isTelemetryBacked() {
        return false;
    }

    private Decimal nz(Decimal d) {
        return (d == null) ? 0 : d;
    }
}
