/**
 * EstimateFootprint — agent-door invocable action (SPEC §S.11, canon C4/C5).
 * Thin marshaller: each Request carries ONE serialized OhmDTO.FootprintRequest (blank =>
 * the modeled org-default baseline at the C6 volume scenario) and delegates to the
 * SINGULAR OhmFootprintService.estimate(FootprintRequest) per element — the same engine
 * the aura door calls, so the two doors can never diverge (C5).
 * Pure computation: no SOQL, no DML, no callout.
 */
public with sharing class EstimateFootprint {

    @InvocableMethod(
        label='Estimate Environmental Footprint'
        description='Estimates the annual energy (Wh), water (mL), and CO2e (g) footprint of an agentic workload as Low/Central/High uncertainty bands. Pass a footprint request JSON for a specific artifact, or leave it blank for the modeled org-default baseline. All figures are modeled, not telemetry, and every assumption used is returned.'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        if (requests == null || requests.isEmpty()) {
            return out;
        }

        OhmFootprintService footprint = new OhmFootprintService();
        VolumeProvider volume = new AssumptionVolumeProvider();

        for (Request r : requests) {
            Response resp = new Response();
            try {
                OhmDTO.FootprintRequest req;
                if (r != null && String.isNotBlank(r.requestJson)) {
                    req = (OhmDTO.FootprintRequest) JSON.deserialize(r.requestJson, OhmDTO.FootprintRequest.class);
                } else {
                    // Org-default baseline: reference tokens, multiplier 1.0, C6 volume scenario.
                    OhmDTO.VolumeInput v = volume.defaultVolume();
                    req = new OhmDTO.FootprintRequest();
                    req.annualCalls = volume.annualCalls(v);
                    req.modelAssumed = true;
                    req.scenarioLabel = v.scenarioLabel;
                }

                OhmDTO.FootprintResponse fp = footprint.estimate(req);
                resp.energyWhLow = fp.energyWhLow;
                resp.energyWhCentral = fp.energyWhCentral;
                resp.energyWhHigh = fp.energyWhHigh;
                resp.waterMlCentral = fp.waterMlCentral;
                resp.co2eGCentral = fp.co2eGCentral;
                resp.annualCalls = fp.annualCalls;
                resp.assumptionsJson = JSON.serialize(fp.assumptions);
                resp.footprintJson = JSON.serialize(fp);
                resp.summary = 'Modeled annual footprint at ' +
                    ((req.scenarioLabel == null) ? 'the given volume' : req.scenarioLabel) + ': ' +
                    scaled(fp.energyWhCentral) + ' Wh energy (range ' + scaled(fp.energyWhLow) + '-' +
                    scaled(fp.energyWhHigh) + '), ' + scaled(fp.waterMlCentral) + ' mL water, ' +
                    scaled(fp.co2eGCentral) + ' g CO2e. Modeled estimate, not telemetry — confidence ' +
                    fp.confidence + '; all assumptions disclosed in the assumptions JSON.';
            } catch (Exception e) {
                resp.summary = 'Error: ' + e.getMessage();
            }
            out.add(resp);
        }
        return out;
    }

    private static String scaled(Decimal d) {
        return (d == null) ? '0' : String.valueOf(d.setScale(1));
    }

    public class Request {
        @InvocableVariable(
            label='Report Id'
            description='Optional Id of the Agent Audit Report this estimate belongs to (context only).'
            required=false)
        public String reportId;
        @InvocableVariable(
            label='Footprint Request JSON'
            description='One serialized footprint request (boundModel, tokensPerInference, annualCalls). Leave blank for the modeled org-default baseline.'
            required=false)
        public String requestJson;
    }

    public class Response {
        @InvocableVariable(label='Energy Wh Low' description='Annual energy, low band (Wh).')
        public Decimal energyWhLow;
        @InvocableVariable(label='Energy Wh Central' description='Annual energy, central band (Wh).')
        public Decimal energyWhCentral;
        @InvocableVariable(label='Energy Wh High' description='Annual energy, high band (Wh).')
        public Decimal energyWhHigh;
        @InvocableVariable(label='Water mL Central' description='Annual water use, central band (mL).')
        public Decimal waterMlCentral;
        @InvocableVariable(label='CO2e g Central' description='Annual CO2 equivalent, central band (g).')
        public Decimal co2eGCentral;
        @InvocableVariable(label='Annual Calls' description='Annual inference calls the estimate assumes.')
        public Decimal annualCalls;
        @InvocableVariable(label='Assumptions JSON' description='Every constant and assumption the estimate used (F10 disclosure).')
        public String assumptionsJson;
        @InvocableVariable(label='Footprint JSON' description='Full serialized footprint response with all Low/Central/High bands. Do not parse.')
        public String footprintJson;
        @InvocableVariable(label='Summary' description='Natural-language footprint result with provenance caveat.')
        public String summary;
    }
}
