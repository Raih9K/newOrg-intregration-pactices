@isTest
public class ProductExternalUpdateQueueableTest {
    
    public class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(201);
            res.setBody('{"id": 12345}');
            return res;
        }
    }
    
    @isTest
    static void testQueueable() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        ProductCatalog cat = new ProductCatalog(Name = 'Test Catalog');
        insert cat;
        
        ProductCategory category = new ProductCategory(Name = 'Test Category', CatalogId = cat.Id, External_Id__c = '1');
        insert category;
        
        Product2 prod = new Product2(
            Name = 'Original Name',
            Fake_Store_Price__c = 10.0,
            Status__c = 'Draft',
            IsActive = true,
            Category__c = category.Id
        );
        insert prod;
        
        Test.startTest();
        System.enqueueJob(new ProductExternalUpdateQueueable(new List<Id>{ prod.Id }));
        Test.stopTest();
        
        Product2 updated = [SELECT ExternalId FROM Product2 WHERE Id = :prod.Id];
        System.assertEquals('12345', updated.ExternalId);
    }
}
