@IsTest
private class OhmDTOTest {
    @IsTest
    static void test_C3_vocabularyRoundTrip() {
        OhmDTO.FootprintResponse r = new OhmDTO.FootprintResponse();
        r.energyWhLow = 1; r.energyWhCentral = 2; r.energyWhHigh = 3;
        r.waterMlLow = 4; r.waterMlCentral = 5; r.waterMlHigh = 6;
        r.co2eGLow = 7; r.co2eGCentral = 8; r.co2eGHigh = 9;
        String js = JSON.serialize(r);

        System.assert(js.contains('energyWhLow'), 'has energyWhLow');
        System.assert(js.contains('energyWhCentral'), 'has energyWhCentral');
        System.assert(js.contains('energyWhHigh'), 'has energyWhHigh');
        System.assert(js.contains('waterMlCentral'), 'has waterMlCentral');
        System.assert(js.contains('co2eGCentral'), 'has co2eGCentral');
        // C3 — no mid/point vocabulary
        System.assert(!js.contains('mid'), 'no mid');
        System.assert(!js.contains('point'), 'no point');

        OhmDTO.FootprintResponse back = (OhmDTO.FootprintResponse) JSON.deserialize(js, OhmDTO.FootprintResponse.class);
        System.assertEquals(2, back.energyWhCentral, 'lossless round-trip');
        System.assertEquals(9, back.co2eGHigh);
    }

    @IsTest
    static void test_agentModel_defaults() {
        OhmDTO.AgentModel g = new OhmDTO.AgentModel();
        System.assertNotEquals(null, g.agentsById);
        System.assertNotEquals(null, g.actions);
        System.assertNotEquals(null, g.discoveryErrors);
        System.assertEquals(0, g.promptTemplateCount);
    }

    @IsTest
    static void test_remediationInput_shape() {
        OhmDTO.RemediationInputDTO d = new OhmDTO.RemediationInputDTO();
        d.fixType = 'Trim_Instructions';
        d.estimatedSavingsCentralWh = 12.5;
        String js = JSON.serialize(d);
        System.assert(js.contains('estimatedSavingsCentralWh'), 'C12 field present');
    }
}
