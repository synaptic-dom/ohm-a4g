@IsTest
private class OhmSalesforceApiTest {
    private class ApiMock implements HttpCalloutMock {
        Integer tokenCalls = 0;
        Integer sourceCalls = 0;
        Integer sourceStatus = 200;
        Boolean oauthFailure = false;
        String sourceBody = '<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/"><env:Body><listMetadataResponse xmlns="http://soap.sforce.com/2006/04/metadata"><result><fullName>Example</fullName></result></listMetadataResponse></env:Body></env:Envelope>';
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            if (request.getEndpoint().endsWith('/services/oauth2/token')) {
                tokenCalls++;
                System.assertEquals('POST', request.getMethod());
                System.assert(request.getBody().contains('grant_type=client_credentials'));
                System.assert(request.getBody().contains('{!$Credential.Ohm_Salesforce_Auth.ClientSecretEncoded}'));
                response.setStatusCode(oauthFailure ? 400 : 200);
                response.setBody(oauthFailure ? '{"error":"invalid_client","secret":"do-not-expose"}' : '{"access_token":"unit-test-session"}');
            } else {
                sourceCalls++;
                if (request.getEndpoint().contains('/services/Soap/m/')) {
                    System.assertEquals('POST', request.getMethod());
                    System.assert(request.getBody().contains('<sessionId>unit-test-session</sessionId>'));
                    System.assertEquals('listMetadata', request.getHeader('SOAPAction'));
                } else {
                    System.assertEquals('GET', request.getMethod());
                    System.assertEquals('Bearer unit-test-session', request.getHeader('Authorization'));
                }
                response.setStatusCode(sourceStatus);
                response.setBody(sourceBody);
            }
            return response;
        }
    }

    @IsTest static void authenticatesSoapAndReusesTransactionToken() {
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        Dom.Document result = OhmSalesforceApi.metadata('listMetadata', '<queries><type>AiAuthoringBundle</type></queries><asOfVersion>67.0</asOfVersion>');
        System.assert(result.toXmlString().contains('Example'));
        OhmSalesforceApi.metadata('listMetadata', '<queries><type>GenAiPromptTemplate</type></queries><asOfVersion>67.0</asOfVersion>');
        System.assertEquals(1, mock.tokenCalls);
        System.assertEquals(2, mock.sourceCalls);
    }

    @IsTest static void onlyAllowsMetadataReadOperationsAndSameOrgPaths() {
        ApiMock mock = new ApiMock();
        Test.setMock(HttpCalloutMock.class, mock);
        try { OhmSalesforceApi.metadata('deploy', '<zipFile>anything</zipFile>'); System.assert(false); }
        catch (OhmSalesforceApi.SourceApiException ex) { System.assertEquals(false, ex.retryable); }
        try { OhmSalesforceApi.getJson('https://outside.example/services/data/v67.0/'); System.assert(false); }
        catch (OhmSalesforceApi.SourceApiException ex) { System.assertEquals(false, ex.retryable); }
        System.assertEquals(0, mock.tokenCalls);
    }

    @IsTest static void readsJsonWithBearerToken() {
        ApiMock mock = new ApiMock(); mock.sourceBody = '{"id":"template-id","fields":{}}';
        Test.setMock(HttpCalloutMock.class, mock);
        System.assertEquals('template-id', OhmSalesforceApi.getJson('/services/data/v67.0/einstein/prompt-templates/Example/versions').get('id'));
    }

    @IsTest static void authFailuresDoNotExposeServerSecrets() {
        ApiMock mock = new ApiMock(); mock.oauthFailure = true;
        Test.setMock(HttpCalloutMock.class, mock);
        try { OhmSalesforceApi.metadata('listMetadata', ''); System.assert(false); }
        catch (OhmSalesforceApi.SourceApiException ex) {
            System.assertEquals(false, ex.retryable);
            System.assertEquals(400, ex.httpStatus);
            System.assert(!ex.getMessage().contains('do-not-expose'));
        }
        System.assertEquals(0, mock.sourceCalls);
    }

    @IsTest static void soapFaultIsExplicitAndDoesNotExposeBody() {
        ApiMock mock = new ApiMock(); mock.sourceStatus = 500;
        mock.sourceBody = '<Envelope><Body><Fault><faultcode>sf:INVALID_SESSION_ID</faultcode><faultstring>private server detail</faultstring></Fault></Body></Envelope>';
        Test.setMock(HttpCalloutMock.class, mock);
        try { OhmSalesforceApi.metadata('listMetadata', ''); System.assert(false); }
        catch (OhmSalesforceApi.SourceApiException ex) {
            System.assertEquals(false, ex.retryable);
            System.assert(ex.getMessage().contains('INVALID_SESSION_ID'));
            System.assert(!ex.getMessage().contains('private server detail'));
        }
    }

    @IsTest static void throttlingIsRetryableButPermissionsAreNot() {
        ApiMock mock = new ApiMock(); mock.sourceStatus = 429; mock.sourceBody = '{}';
        Test.setMock(HttpCalloutMock.class, mock);
        try { OhmSalesforceApi.metadata('listMetadata', ''); System.assert(false); }
        catch (OhmSalesforceApi.SourceApiException ex) { System.assertEquals(true, ex.retryable); }
        mock.sourceStatus = 403;
        try { OhmSalesforceApi.metadata('listMetadata', ''); System.assert(false); }
        catch (OhmSalesforceApi.SourceApiException ex) { System.assertEquals(false, ex.retryable); }
    }

    @IsTest static void oversizedSourcesFailWithoutTruncation() {
        ApiMock mock = new ApiMock(); Test.setMock(HttpCalloutMock.class, mock);
        OhmSalesforceApi.maxResponseChars = 100;
        try { OhmSalesforceApi.metadata('listMetadata', ''); System.assert(false); }
        catch (OhmSalesforceApi.SourceApiException ex) {
            System.assertEquals(false, ex.retryable);
            System.assert(ex.getMessage().contains('supported retrieval size'));
        }
    }
}
