@IsTest
private class OhmSeverityTest {
    @IsTest
    static void test_bandCutoffs() {
        System.assertEquals('Medium', OhmSeverity.band(0.66), '0.66 -> Medium');
        System.assertEquals('High', OhmSeverity.band(0.67), '0.67 -> High');
        System.assertEquals('Low', OhmSeverity.band(0.33), '0.33 -> Low');
        System.assertEquals('Medium', OhmSeverity.band(0.34), '0.34 -> Medium');
        System.assertEquals('High', OhmSeverity.band(1.0), '1.0 -> High');
        System.assertEquals('Low', OhmSeverity.band(0), '0 -> Low');
        System.assertEquals('Low', OhmSeverity.band(null), 'null -> Low');
    }
}
