/** Read-only Salesforce API transport. OAuth secrets stay in an External Credential.
 * A fresh client-credentials token is held only in this transaction. SOAP Metadata API
 * requires SessionHeader; a Bearer HTTP header alone does not authenticate that API.
 */
public with sharing class OhmSalesforceApi {
    public static final String API_VERSION = '67.0';
    private static final String BASE = 'callout:Ohm_Salesforce';
    @TestVisible private static Integer maxResponseChars = 4000000;
    private static String accessToken;

    public class SourceApiException extends Exception {
        public Boolean retryable = false;
        public Integer httpStatus;
    }

    public static Dom.Document metadata(String operation, String innerXml) {
        if (!new Set<String>{'listMetadata', 'readMetadata', 'retrieve', 'checkRetrieveStatus', 'describeMetadata'}.contains(operation)) {
            throw failure('Unsupported source-read operation.', null, false);
        }
        String token = token();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(BASE + '/services/Soap/m/' + API_VERSION);
        request.setMethod('POST');
        request.setTimeout(120000);
        request.setHeader('Content-Type', 'text/xml; charset=UTF-8');
        request.setHeader('SOAPAction', operation);
        request.setBody('<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">'
            + '<env:Header><SessionHeader xmlns="http://soap.sforce.com/2006/04/metadata"><sessionId>'
            + token.escapeXml() + '</sessionId></SessionHeader></env:Header><env:Body><' + operation
            + ' xmlns="http://soap.sforce.com/2006/04/metadata">' + (innerXml == null ? '' : innerXml)
            + '</' + operation + '></env:Body></env:Envelope>');
        HttpResponse response = send(request);
        if (response.getStatusCode() >= 400 && response.getStatusCode() < 500) { assertSuccess(response); }
        String body = checkedBody(response);
        Dom.Document document = new Dom.Document();
        try { document.load(body); }
        catch (Exception ex) { throw failure('Salesforce returned unreadable metadata. Retry the source refresh.', response.getStatusCode(), true); }
        Dom.XmlNode fault = find(document.getRootElement(), 'Fault');
        if (fault != null) {
            Dom.XmlNode code = find(fault, 'faultcode');
            String faultCode = code == null ? 'UNKNOWN' : code.getText();
            if (faultCode.contains('INVALID_SESSION_ID')) { accessToken = null; }
            throw failure('Salesforce metadata retrieval failed (' + safeCode(faultCode) + '). Check the source connection and metadata permissions.', response.getStatusCode(), faultCode.contains('SERVER_UNAVAILABLE') || faultCode.contains('REQUEST_LIMIT_EXCEEDED'));
        }
        assertSuccess(response);
        return document;
    }

    public static Map<String, Object> getJson(String path) {
        if (String.isBlank(path) || !path.startsWith('/services/data/v' + API_VERSION + '/')
            || path.contains('..') || path.contains('//') || path.contains('{!') || path.contains('\r') || path.contains('\n')) {
            throw failure('Invalid Salesforce source-read path.', null, false);
        }
        HttpRequest request = new HttpRequest();
        request.setEndpoint(BASE + path);
        request.setMethod('GET');
        request.setHeader('Authorization', 'Bearer ' + token());
        request.setHeader('Accept', 'application/json');
        request.setTimeout(120000);
        HttpResponse response = send(request);
        assertSuccess(response);
        try { return (Map<String, Object>)JSON.deserializeUntyped(checkedBody(response)); }
        catch (SourceApiException ex) { throw ex; }
        catch (Exception ex) { throw failure('Salesforce returned unreadable source data.', response.getStatusCode(), true); }
    }

    private static String token() {
        if (String.isNotBlank(accessToken)) { return accessToken; }
        HttpRequest request = new HttpRequest();
        request.setEndpoint(BASE + '/services/oauth2/token');
        request.setMethod('POST');
        request.setTimeout(30000);
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        // The setup script stores URL-encoded values encrypted in the credential principal.
        request.setBody('grant_type=client_credentials&client_id={!$Credential.Ohm_Salesforce_Auth.ClientIdEncoded}'
            + '&client_secret={!$Credential.Ohm_Salesforce_Auth.ClientSecretEncoded}');
        HttpResponse response = send(request);
        if (response.getStatusCode() < 200 || response.getStatusCode() >= 300) {
            throw failure('Salesforce source connection could not authenticate. Check its client credentials and execution user.', response.getStatusCode(), response.getStatusCode() == 429 || response.getStatusCode() >= 500);
        }
        try {
            Map<String, Object> result = (Map<String, Object>)JSON.deserializeUntyped(checkedBody(response));
            accessToken = (String)result.get('access_token');
        } catch (Exception ex) { throw failure('Salesforce source connection returned an invalid authentication response.', response.getStatusCode(), false); }
        if (String.isBlank(accessToken)) { throw failure('Salesforce source connection returned no access token.', response.getStatusCode(), false); }
        return accessToken;
    }

    private static HttpResponse send(HttpRequest request) {
        try { return new Http().send(request); }
        catch (Exception ex) {
            throw failure('Could not reach the Salesforce source connection. Check Named Credential Ohm_Salesforce and principal access.', null, true);
        }
    }

    private static String checkedBody(HttpResponse response) {
        String body = response.getBody();
        if (body == null || body.length() > maxResponseChars) {
            throw failure('Salesforce source response exceeds the supported retrieval size. Select a smaller process.', response.getStatusCode(), false);
        }
        return body;
    }

    private static void assertSuccess(HttpResponse response) {
        Integer code = response.getStatusCode();
        if (code < 200 || code >= 300) {
            if (code == 401) { accessToken = null; }
            throw failure('Salesforce source request failed (HTTP ' + code + ').', code, code == 429 || code >= 500);
        }
    }

    private static Dom.XmlNode find(Dom.XmlNode node, String name) {
        if (node == null || node.getName() == name) { return node; }
        for (Dom.XmlNode child : node.getChildElements()) {
            Dom.XmlNode found = find(child, name);
            if (found != null) { return found; }
        }
        return null;
    }

    private static String safeCode(String value) {
        return value == null ? 'UNKNOWN' : value.replaceAll('[^A-Za-z0-9_:.-]', '').left(100);
    }

    private static SourceApiException failure(String message, Integer status, Boolean retryable) {
        SourceApiException error = new SourceApiException(message);
        error.httpStatus = status;
        error.retryable = retryable;
        return error;
    }
}
