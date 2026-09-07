/**
 * OhmFootprintService — THE one footprint engine (SPEC §S.7, canon C5).
 *   estimate(FootprintRequest) : FootprintResponse                         (singular engine)
 *   estimateForArtifact(Finding, VolumeInput) : FootprintResponse
 *   savingsFor(Finding, VolumeInput) : FootprintResponse                   (re-run with one fixed param)
 *   sumAll(List<FootprintResponse>) : FootprintResponse                    (element-wise band sum)
 * All figures band-pinned to Ohm_Constants; {Low,Central,High} vocabulary (C3);
 * telemetryBacked=false, confidence='Low'; assumptions discloses every constant (F10).
 */
public with sharing class OhmFootprintService {

    private static final VolumeProvider VOLUME = new AssumptionVolumeProvider();

    // ---------- the ONE engine ----------
    public OhmDTO.FootprintResponse estimate(OhmDTO.FootprintRequest req) {
        OhmConstants c = OhmConstants.load();
        OhmConstants.Band energy = c.energyPerPromptWh();
        OhmConstants.Band grid = c.gridIntensityGco2ePerWh();
        OhmConstants.Band water = c.waterMlPerWh();
        Integer ref = c.referencePromptTokens();

        OhmDTO.FootprintResponse r = new OhmDTO.FootprintResponse();
        if (req == null) {
            req = new OhmDTO.FootprintRequest();
        }

        ModelRegistry.ModelInfo model = ModelRegistry.lookup(req.boundModel);
        Decimal multiplier = model.rateCardMultiplier;
        Boolean modelAssumed = (req.modelAssumed == true) || model.assumed;

        Decimal tokens = (req.tokensPerInference == null) ? ref : req.tokensPerInference;
        Decimal annualCalls = (req.annualCalls == null) ? 0 : req.annualCalls;
        Decimal tokenRatio = (ref == 0) ? 0 : (tokens / (Decimal) ref);

        // per-inference Wh per band
        Decimal perLow = energy.low * multiplier * tokenRatio;
        Decimal perCentral = energy.central * multiplier * tokenRatio;
        Decimal perHigh = energy.high * multiplier * tokenRatio;

        r.energyWhLow = perLow * annualCalls;
        r.energyWhCentral = perCentral * annualCalls;
        r.energyWhHigh = perHigh * annualCalls;

        r.co2eGLow = r.energyWhLow * grid.low;
        r.co2eGCentral = r.energyWhCentral * grid.central;
        r.co2eGHigh = r.energyWhHigh * grid.high;

        r.waterMlLow = r.energyWhLow * water.low;
        r.waterMlCentral = r.energyWhCentral * water.central;
        r.waterMlHigh = r.energyWhHigh * water.high;

        r.annualCalls = annualCalls;
        r.perInferenceWh = perCentral;
        r.telemetryBacked = false;
        r.confidence = 'Low';
        r.assumptions = new Map<String, Object>{
            'energyPerPromptWh' => new Map<String, Object>{ 'low' => energy.low, 'central' => energy.central, 'high' => energy.high },
            'gridIntensityGco2ePerWh' => new Map<String, Object>{ 'low' => grid.low, 'central' => grid.central, 'high' => grid.high },
            'waterMlPerWh' => new Map<String, Object>{ 'low' => water.low, 'central' => water.central, 'high' => water.high },
            'referencePromptTokens' => ref,
            'tokensPerInference' => tokens,
            'rateCardMultiplier' => multiplier,
            'modelTier' => model.tier,
            'modelAssumed' => modelAssumed,
            'annualCalls' => annualCalls,
            'telemetryBacked' => false,
            'methodologyVersion' => c.methodologyVersion()
        };
        return r;
    }

    // ---------- per-artifact convenience ----------
    public OhmDTO.FootprintResponse estimateForArtifact(OhmDTO.Finding f, OhmDTO.VolumeInput v) {
        return estimate(baseRequest(f, v));
    }

    /**
     * savingsFor — re-run the engine with the ONE fixed parameter per signal.
     *  (a) removed call        => savings = full baseline
     *  (b) cheaper multiplier  => savings = baseline × (mBound − mRec)  [= footprint × (1 − mRec/mBound)]
     *  (c) reduced tokens      => savings = baseline(total) − baseline(soft)
     *  (d) reduced callsPerTurn=> savings = baseline(1+extra) − baseline(1)
     */
    public OhmDTO.FootprintResponse savingsFor(OhmDTO.Finding f, OhmDTO.VolumeInput v) {
        if (f == null || f.reviewRequired == true) {
            return zero();
        }
        OhmConstants c = OhmConstants.load();
        OhmDTO.FootprintRequest req = baseRequest(f, v);
        OhmDTO.FootprintResponse baseline = estimate(req);

        if (f.signalType == LlmWhereDeterministicDetector.SIGNAL) {
            return f.reviewRequired == false ? baseline : zero();

        } else if (f.signalType == ModelRightSizingDetector.SIGNAL) {
            ModelRegistry.ModelInfo current = ModelRegistry.lookup(f.boundModel);
            ModelRegistry.ModelInfo target = ModelRegistry.lookup(f.recommendedTarget);
            if (current.assumed || target.assumed || String.isBlank(f.recommendedTarget)) { return zero(); }
            Decimal ratio = 1 - target.rateCardMultiplier / current.rateCardMultiplier;
            return scale(baseline, Math.max(0, ratio));

        } else if (f.signalType == InstructionBloatDetector.SIGNAL) {
            OhmDTO.FootprintRequest fixedReq = cloneReq(req);
            fixedReq.tokensPerInference = c.softThresholdFor(f.artifactType);
            return subtract(baseline, estimate(fixedReq));

        } else if (f.signalType == RedundantCallDetector.SIGNAL) {
            if (f.reviewRequired != false) { return zero(); }
            OhmDTO.FootprintRequest fixedReq = cloneReq(req);
            fixedReq.annualCalls = VOLUME.annualCalls(VOLUME.withCallsPerTurn(resolveVolume(v), 1));
            return subtract(baseline, estimate(fixedReq));
        }
        return zero();
    }

    // ---------- org-wide totals (NOT a second engine) ----------
    public OhmDTO.FootprintResponse sumAll(List<OhmDTO.FootprintResponse> parts) {
        OhmDTO.FootprintResponse total = zero();
        if (parts == null) {
            return total;
        }
        for (OhmDTO.FootprintResponse p : parts) {
            if (p == null) { continue; }
            total.energyWhLow = nz(total.energyWhLow) + nz(p.energyWhLow);
            total.energyWhCentral = nz(total.energyWhCentral) + nz(p.energyWhCentral);
            total.energyWhHigh = nz(total.energyWhHigh) + nz(p.energyWhHigh);
            total.co2eGLow = nz(total.co2eGLow) + nz(p.co2eGLow);
            total.co2eGCentral = nz(total.co2eGCentral) + nz(p.co2eGCentral);
            total.co2eGHigh = nz(total.co2eGHigh) + nz(p.co2eGHigh);
            total.waterMlLow = nz(total.waterMlLow) + nz(p.waterMlLow);
            total.waterMlCentral = nz(total.waterMlCentral) + nz(p.waterMlCentral);
            total.waterMlHigh = nz(total.waterMlHigh) + nz(p.waterMlHigh);
            total.annualCalls = nz(total.annualCalls) + nz(p.annualCalls);
        }
        return total;
    }

    // ---------- private helpers ----------
    private OhmDTO.FootprintRequest baseRequest(OhmDTO.Finding f, OhmDTO.VolumeInput v) {
        OhmConstants c = OhmConstants.load();
        OhmDTO.VolumeInput vol = resolveVolume(v);
        OhmDTO.FootprintRequest req = new OhmDTO.FootprintRequest();
        req.tokensPerInference = c.referencePromptTokens();
        req.boundModel = f == null ? null : f.boundModel;
        req.modelAssumed = ModelRegistry.lookup(req.boundModel).assumed;

        if (f != null) {
            req.artifactId = f.artifactToolingId;
            req.artifactType = f.artifactType;
            Integer soft = c.softThresholdFor(f.artifactType);
            if (f.signalType == InstructionBloatDetector.SIGNAL && f.metricValue != null) {
                req.tokensPerInference = f.metricValue + soft; // total = excess + soft
            }
            if (f.signalType == RedundantCallDetector.SIGNAL && f.metricValue != null) {
                vol = VOLUME.withCallsPerTurn(vol, 1 + f.metricValue);
            }
        }
        req.annualCalls = VOLUME.annualCalls(vol);
        req.scenarioLabel = vol.scenarioLabel;
        return req;
    }

    private OhmDTO.VolumeInput resolveVolume(OhmDTO.VolumeInput v) {
        return (v == null) ? VOLUME.defaultVolume() : v;
    }

    private OhmDTO.FootprintRequest cloneReq(OhmDTO.FootprintRequest src) {
        OhmDTO.FootprintRequest r = new OhmDTO.FootprintRequest();
        r.artifactId = src.artifactId;
        r.artifactType = src.artifactType;
        r.boundModel = src.boundModel;
        r.tokensPerInference = src.tokensPerInference;
        r.annualCalls = src.annualCalls;
        r.modelAssumed = src.modelAssumed;
        r.scenarioLabel = src.scenarioLabel;
        return r;
    }

    private OhmDTO.FootprintResponse scale(OhmDTO.FootprintResponse a, Decimal k) {
        OhmDTO.FootprintResponse r = new OhmDTO.FootprintResponse();
        r.energyWhLow = nz(a.energyWhLow) * k;
        r.energyWhCentral = nz(a.energyWhCentral) * k;
        r.energyWhHigh = nz(a.energyWhHigh) * k;
        r.co2eGLow = nz(a.co2eGLow) * k;
        r.co2eGCentral = nz(a.co2eGCentral) * k;
        r.co2eGHigh = nz(a.co2eGHigh) * k;
        r.waterMlLow = nz(a.waterMlLow) * k;
        r.waterMlCentral = nz(a.waterMlCentral) * k;
        r.waterMlHigh = nz(a.waterMlHigh) * k;
        r.annualCalls = a.annualCalls;
        r.perInferenceWh = nz(a.perInferenceWh) * k;
        r.telemetryBacked = false;
        r.confidence = 'Low';
        r.assumptions = a.assumptions;
        return r;
    }

    private OhmDTO.FootprintResponse subtract(OhmDTO.FootprintResponse a, OhmDTO.FootprintResponse b) {
        OhmDTO.FootprintResponse r = new OhmDTO.FootprintResponse();
        r.energyWhLow = nz(a.energyWhLow) - nz(b.energyWhLow);
        r.energyWhCentral = nz(a.energyWhCentral) - nz(b.energyWhCentral);
        r.energyWhHigh = nz(a.energyWhHigh) - nz(b.energyWhHigh);
        r.co2eGLow = nz(a.co2eGLow) - nz(b.co2eGLow);
        r.co2eGCentral = nz(a.co2eGCentral) - nz(b.co2eGCentral);
        r.co2eGHigh = nz(a.co2eGHigh) - nz(b.co2eGHigh);
        r.waterMlLow = nz(a.waterMlLow) - nz(b.waterMlLow);
        r.waterMlCentral = nz(a.waterMlCentral) - nz(b.waterMlCentral);
        r.waterMlHigh = nz(a.waterMlHigh) - nz(b.waterMlHigh);
        r.annualCalls = a.annualCalls;
        r.perInferenceWh = nz(a.perInferenceWh) - nz(b.perInferenceWh);
        r.telemetryBacked = false;
        r.confidence = 'Low';
        r.assumptions = a.assumptions;
        return r;
    }

    private OhmDTO.FootprintResponse zero() {
        OhmDTO.FootprintResponse r = new OhmDTO.FootprintResponse();
        r.energyWhLow = 0; r.energyWhCentral = 0; r.energyWhHigh = 0;
        r.co2eGLow = 0; r.co2eGCentral = 0; r.co2eGHigh = 0;
        r.waterMlLow = 0; r.waterMlCentral = 0; r.waterMlHigh = 0;
        r.annualCalls = 0; r.perInferenceWh = 0;
        r.telemetryBacked = false; r.confidence = 'Low';
        r.assumptions = new Map<String, Object>();
        return r;
    }

    private Decimal nz(Decimal d) {
        return (d == null) ? 0 : d;
    }
}
