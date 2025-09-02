@isTest
global class RewardsCalloutServiceMock implements HttpCalloutMock {
    public static String lastRequestBody;
    global HTTPResponse respond(HTTPRequest req) {
        lastRequestBody = req.getBody();
        HttpResponse res = new HttpResponse();
        res.setHeader('Content-Type', 'application/json');
        res.setBody('{"status":"success"}');
        res.setStatusCode(200);
        return res;
    }
}