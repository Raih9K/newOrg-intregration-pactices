@isTest
public class ProductSyncEmailHandlerTest {
    
    // Setup test data to insert a default ProductCatalog record.
    // This prevents "You have uncommitted work pending" callout exceptions during asynchronous 
    // execution of ProductSyncQueueable triggered by the email handler.
    @testSetup
    static void setupTestData() {
        ProductCatalog catalog = new ProductCatalog(Name = 'Test Catalog');
        insert catalog;
    }

    public class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            
            if (req.getEndpoint().endsWith('/auth/login')) {
                res.setStatusCode(200);
                res.setBody('{"access_token": "mocked_bearer_token"}');
            } else if (req.getEndpoint().endsWith('/categories')) {
                res.setStatusCode(200);
                res.setBody('[{"id": 1, "name": "Clothes", "image": "https://placehold.co/600x400"}]');
            } else if (req.getEndpoint().endsWith('/products')) {
                res.setStatusCode(200);
                res.setBody('[{"id": 10, "title": "T-Shirt", "price": 25, "description": "Cotton t-shirt", "images": ["https://placehold.co/600x400"], "category": {"id": 1, "name": "Clothes"}}]');
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }
    
    @isTest
    static void testEmailHandler() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Messaging.InboundEmail email = new Messaging.InboundEmail();
        Messaging.InboundEnvelope env = new Messaging.InboundEnvelope();
        
        email.subject = 'Sync Request';
        email.fromAddress = 'test@example.com';
        email.plainTextBody = 'Start Sync';
        
        ProductSyncEmailHandler handler = new ProductSyncEmailHandler();
        
        Test.startTest();
        Messaging.InboundEmailResult result = handler.handleInboundEmail(email, env);
        Test.stopTest();
        
        System.assertEquals(true, result.success);
        
        List<System_Log__c> logs = [SELECT Log_Level__c, Log_Type__c, Source_Email__c, Status__c FROM System_Log__c];
        System.assertEquals(1, logs.size());
        System.assertEquals('INFO', logs[0].Log_Level__c);
        System.assertEquals('Inbound Email', logs[0].Log_Type__c);
        System.assertEquals('test@example.com', logs[0].Source_Email__c);
        System.assertEquals('Success', logs[0].Status__c);
    }
}
