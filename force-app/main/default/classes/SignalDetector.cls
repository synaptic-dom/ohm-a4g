/**
 * SignalDetector — one waste-signal heuristic over the discovery graph (SPEC §S.6).
 * Detectors NEVER throw on malformed input: they degrade to an empty finding list.
 */
public interface SignalDetector {
    List<OhmDTO.Finding> detect(OhmDTO.AgentModel g);
}
