public with sharing class OhmSpikeAction {
    public class Request {
        @InvocableVariable(required=true label='Input' description='Text to echo back')
        public String input;
    }

    public class Response {
        @InvocableVariable(label='Output' description='Echoed text prefixed with pong:')
        public String output;
    }

    @InvocableMethod(label='Ohm Spike Ping' description='Echoes the input back prefixed with "pong: " to prove an Agentforce apex action binds to an @InvocableMethod.')
    public static List<Response> ping(List<Request> requests) {
        List<Response> results = new List<Response>();
        for (Request req : requests) {
            Response res = new Response();
            res.output = 'pong: ' + req.input;
            results.add(res);
        }
        return results;
    }
}
