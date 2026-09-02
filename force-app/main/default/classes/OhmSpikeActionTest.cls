@IsTest
private class OhmSpikeActionTest {
    @IsTest
    static void ping_echoesInputWithPongPrefix() {
        OhmSpikeAction.Request req = new OhmSpikeAction.Request();
        req.input = 'hello';

        Test.startTest();
        List<OhmSpikeAction.Response> results = OhmSpikeAction.ping(new List<OhmSpikeAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One response per request');
        System.assertEquals('pong: hello', results[0].output, 'Output must echo input with pong: prefix');
    }

    @IsTest
    static void ping_handlesBulkRequests() {
        List<OhmSpikeAction.Request> reqs = new List<OhmSpikeAction.Request>();
        for (Integer i = 0; i < 3; i++) {
            OhmSpikeAction.Request r = new OhmSpikeAction.Request();
            r.input = 'n' + i;
            reqs.add(r);
        }

        Test.startTest();
        List<OhmSpikeAction.Response> results = OhmSpikeAction.ping(reqs);
        Test.stopTest();

        System.assertEquals(3, results.size(), 'One response per request in bulk');
        System.assertEquals('pong: n0', results[0].output);
        System.assertEquals('pong: n2', results[2].output);
    }
}
