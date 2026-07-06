@isTest
public class Product2TriggerTest {
    
    public class MockHttpResponseGenerator implements HttpCalloutMock {
        public HTTPResponse respond(HTTPRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            res.setStatusCode(200);
            res.setBody('{"id": 999, "access_token": "mocked_bearer_token"}');
            return res;
        }
    }
    
    @isTest
    static void testChangeControlFlow() {
        Test.setMock(HttpCalloutMock.class, new MockHttpResponseGenerator());
        
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User standardUser = new User(
            Alias = 'stdusr', 
            Email='stduser@testorg.com', 
            EmailEncodingKey='UTF-8', 
            LastName='Testing', 
            LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', 
            ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', 
            UserName='stduser_integration_test@testorg.com'
        );
        // Wrap the insertion of the setup objects (User & PermissionSetAssignment) 
        // inside System.runAs(Admin) to separate setup and non-setup DML transactions, 
        // preventing MIXED_DML_OPERATION exceptions when ProductCatalog is inserted next.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert standardUser;
            
            Group qcGroup = [SELECT Id FROM Group WHERE DeveloperName = 'Product_QC_Group' LIMIT 1];
            insert new GroupMember(GroupId = qcGroup.Id, UserOrGroupId = standardUser.Id);
            
            // Assign the newly created Permission Set to the standardUser so they have 
            // the necessary FLS and Object CRUD permissions to edit the Product2 record during the test run.
            PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Product_Integration_Permissions' LIMIT 1];
            insert new PermissionSetAssignment(AssigneeId = standardUser.Id, PermissionSetId = ps.Id);
        }
        
        ProductCatalog cat = new ProductCatalog(Name = 'Test Catalog');
        insert cat;
        
        ProductCategory category = new ProductCategory(Name = 'Test Category', CatalogId = cat.Id, External_Id__c = '1');
        insert category;
        
        // Declare the product variable outside runAs block so it remains accessible in post-update assertions.
        Product2 prod;
        
        // Execute DML as standardUser so they are the owner/creator of the product.
        // This satisfies the allowedSubmitters entry criteria (set to Owner) for the 
        // Product_Edit_Approval process, preventing "NO_APPLICABLE_PROCESS" errors on submit.
        System.runAs(standardUser) {
            prod = new Product2(
                Name = 'Original Name',
                Fake_Store_Price__c = 10.0,
                Status__c = 'Active',
                IsActive = true,
                Category__c = category.Id
            );
            insert prod;

            Test.startTest();
            prod.Name = 'New Proposed Name';
            prod.Fake_Store_Price__c = 15.0;
            update prod;
            Test.stopTest();
        }
        
        Product2 updated = [SELECT Id, Name, Fake_Store_Price__c, Status__c, Proposed_Changes__c FROM Product2 WHERE Id = :prod.Id];
        System.assertEquals('Original Name', updated.Name);
        System.assertEquals(10.0, updated.Fake_Store_Price__c);
        System.assertEquals('Draft', updated.Status__c);
        System.assert(String.isNotBlank(updated.Proposed_Changes__c));
        
        List<ProcessInstance> instances = [SELECT Status, TargetObjectId FROM ProcessInstance WHERE TargetObjectId = :prod.Id];
        System.assertEquals(1, instances.size());
        
        updated.Status__c = 'Active';
        update updated;
        
        Product2 finalProd = [SELECT Id, Name, Fake_Store_Price__c, Status__c, Proposed_Changes__c FROM Product2 WHERE Id = :prod.Id];
        System.assertEquals('New Proposed Name', finalProd.Name);
        System.assertEquals(15.0, finalProd.Fake_Store_Price__c);
        System.assertEquals('Active', finalProd.Status__c);
        System.assert(String.isBlank(finalProd.Proposed_Changes__c));
    }
}
