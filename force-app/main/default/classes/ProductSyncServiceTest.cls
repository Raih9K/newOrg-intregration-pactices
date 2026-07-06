@isTest
public class ProductSyncServiceTest {
    
    // Setup test data to insert a default ProductCatalog record.
    // This is required because the integration service queries and uses a catalog.
    // Pre-inserting the catalog here prevents DML (insert catalog) from running before 
    // HTTP Callouts within the sync service, avoiding "You have uncommitted work pending" exceptions.
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
            } else if (req.getEndpoint().contains('/products/') || (req.getEndpoint().endsWith('/products') && req.getMethod() == 'PUT')) {
                res.setStatusCode(200);
                res.setBody('{"id": 10, "title": "T-Shirt"}');
            } else if (req.getEndpoint().endsWith('/products') && req.getMethod() == 'POST') {
                res.setStatusCode(201);
                res.setBody('{"id": 11, "title": "New Product"}');
            } else if (req.getEndpoint().endsWith('/products') && req.getMethod() == 'GET') {
                res.setStatusCode(200);
                res.setBody('[{"id": 10, "title": "T-Shirt", "price": 25, "description": "Cotton t-shirt", "images": ["https://placehold.co/600x400"], "category": {"id": 1, "name": "Clothes"}}]');
            } else {
                res.setStatusCode(404);
            }
            return res;
        }
    }
    
    @isTest
    static void testSyncEscuelaProducts() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Test.startTest();
        ProductSyncService.syncEscuelaProducts();
        Test.stopTest();
        
        List<ProductCategory> cats = [SELECT Name, External_Id__c, Image_URL__c FROM ProductCategory];
        System.assertEquals(1, cats.size());
        System.assertEquals('Clothes', cats[0].Name);
        System.assertEquals('1', cats[0].External_Id__c);
        
        List<Product2> prods = [SELECT Name, ExternalId, Fake_Store_Price__c, Fake_Store_Image_URL__c, Status__c FROM Product2];
        System.assertEquals(1, prods.size());
        System.assertEquals('T-Shirt', prods[0].Name);
        System.assertEquals('10', prods[0].ExternalId);
        System.assertEquals(25, prods[0].Fake_Store_Price__c);
        System.assertEquals('Active', prods[0].Status__c);
    }

    @isTest
    static void testManualSyncController() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Test.startTest();
        ProductListSyncController.runManualSync();
        Test.stopTest();
        
        List<Product2> prods = [SELECT Name FROM Product2];
        System.assertEquals(1, prods.size());
    }

    @isTest
    static void testSyncSingleProductExisting() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        ProductCategory cat = new ProductCategory(Name = 'Clothes', CatalogId = [SELECT Id FROM ProductCatalog LIMIT 1].Id, External_Id__c = '1');
        insert cat;
        
        Product2 existingProd = new Product2(
            Name = 'T-Shirt',
            Description = 'Cotton t-shirt',
            Price__c = 25,
            ExternalId = '10',
            Category__c = cat.Id,
            IsActive = true
        );
        insert existingProd;
        
        Test.startTest();
        ProductListSyncController.syncSingleProduct(existingProd.Id);
        Test.stopTest();
        
        Product2 updatedProd = [SELECT ExternalId FROM Product2 WHERE Id = :existingProd.Id];
        System.assertEquals('10', updatedProd.ExternalId);
    }

    @isTest
    static void testSyncSingleProductNew() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        ProductCategory cat = new ProductCategory(Name = 'Clothes', CatalogId = [SELECT Id FROM ProductCatalog LIMIT 1].Id, External_Id__c = '1');
        insert cat;
        
        Product2 newProd = new Product2(
            Name = 'New Product',
            Description = 'New Description',
            Price__c = 30,
            Category__c = cat.Id,
            IsActive = true
        );
        insert newProd;
        
        Test.startTest();
        ProductListSyncController.syncSingleProduct(newProd.Id);
        Test.stopTest();
        
        Product2 updatedNewProd = [SELECT ExternalId FROM Product2 WHERE Id = :newProd.Id];
        System.assertEquals('11', updatedNewProd.ExternalId);
    }

    @isTest
    static void testInvocableMethod() {
        // Verifies that ProductListSyncController.runSyncFromFlow() (the @InvocableMethod that 
        // replaced ERP_ProductSyncInvocable) correctly enqueues the bulk sync queueable.
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());

        Test.startTest();
        ProductListSyncController.runSyncFromFlow(new List<Boolean>{ true });
        Test.stopTest();

        List<Product2> products = [SELECT Id FROM Product2];
        System.assertEquals(1, products.size(), 'A product should have been imported by the sync queueable triggered via @InvocableMethod');
    }
}
