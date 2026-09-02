/**
 * VolumeProvider — abstraction over call-volume estimation (SPEC §S.5).
 * Keeps a future TelemetryVolumeProvider swap-in with no caller change.
 * annualCalls is the ONLY volume math in the codebase (canon C6).
 */
public interface VolumeProvider {
    OhmDTO.VolumeInput defaultVolume();
    OhmDTO.VolumeInput withCallsPerTurn(OhmDTO.VolumeInput base, Decimal callsPerTurn);
    Decimal annualCalls(OhmDTO.VolumeInput v);
    Boolean isTelemetryBacked();
}
