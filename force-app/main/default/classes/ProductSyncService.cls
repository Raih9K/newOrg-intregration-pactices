// ProductSyncService: Integration sync processor class.
// Ekhane external API (EscuelaJS) processing, access token, products/categories import logic handle kora hoy.
// Trailhead Reference: "Apex Integration Services" (https://trailhead.salesforce.com/content/learn/modules/apex_integration_services)
// "Asynchronous Apex" (https://trailhead.salesforce.com/content/learn/modules/asynchronous_apex)
public with sharing class ProductSyncService {
    
    private static final String API_BASE_URL = 'https://api.escuelajs.co/api/v1';
    
    // Auth login API standard callout request use token retrieval
    public static String getAccessToken() {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(API_BASE_URL + '/auth/login');
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        
        // Static credentials payload serialization map format
        Map<String, String> credentials = new Map<String, String>{
            'email' => 'john@mail.com',
            'password' => 'changeme'
        };
        request.setBody(JSON.serialize(credentials));
        
        HttpResponse response = http.send(request);
        if (response.getStatusCode() == 200 || response.getStatusCode() == 201) {
            Map<String, Object> results = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
            return (String) results.get('access_token');
        } else {
            throw new CalloutException('Failed to authenticate with EscuelaJS API: ' + response.getStatus() + ' - ' + response.getBody());
        }
    }
    
    // Import categories and products from Escuela API.
    // Callout sequentially first then run DML to prevent "You have uncommitted work pending" exception.
    public static void syncEscuelaProducts() {
        String token = getAccessToken();
        Http http = new Http();
        
        // 1. Fetch Categories (Callout 1)
        HttpRequest catRequest = new HttpRequest();
        catRequest.setEndpoint(API_BASE_URL + '/categories');
        catRequest.setMethod('GET');
        catRequest.setHeader('Authorization', 'Bearer ' + token);
        
        HttpResponse catResponse = http.send(catRequest);
        if (catResponse.getStatusCode() != 200) {
            throw new CalloutException('Failed to fetch categories: ' + catResponse.getStatus() + ' - ' + catResponse.getBody());
        }
        
        // 2. Fetch Products (Callout 2 - Done before any DML to prevent "uncommitted work pending" errors)
        HttpRequest prodRequest = new HttpRequest();
        prodRequest.setEndpoint(API_BASE_URL + '/products');
        prodRequest.setMethod('GET');
        prodRequest.setHeader('Authorization', 'Bearer ' + token);
        
        HttpResponse prodResponse = http.send(prodRequest);
        if (prodResponse.getStatusCode() != 200) {
            throw new CalloutException('Failed to fetch products: ' + prodResponse.getStatus() + ' - ' + prodResponse.getBody());
        }
        
        // --- Shob HTTP Callouts Complete: Ekhon DML operation and data parsing run korbo ---
        List<Object> categoriesJson = (List<Object>) JSON.deserializeUntyped(catResponse.getBody());
        List<ProductCategory> categoriesToUpsert = new List<ProductCategory>();
        
        List<ProductCatalog> catalogs = [SELECT Id FROM ProductCatalog LIMIT 1];
        Id catalogId;
        if (catalogs.isEmpty()) {
            ProductCatalog newCatalog = new ProductCatalog(Name = 'Default Product Catalog');
            insert newCatalog;
            catalogId = newCatalog.Id;
        } else {
            catalogId = catalogs[0].Id;
        }
        
        for (Object obj : categoriesJson) {
            Map<String, Object> catMap = (Map<String, Object>) obj;
            String catId = String.valueOf(catMap.get('id'));
            String catName = (String) catMap.get('name');
            String imageUrl = (String) catMap.get('image');
            
            ProductCategory pc = new ProductCategory(
                Name = catName,
                CatalogId = catalogId,
                External_Id__c = catId,
                Image_URL__c = imageUrl
            );
            categoriesToUpsert.add(pc);
        }
        
        if (!categoriesToUpsert.isEmpty()) {
            Schema.SObjectField externalIdField = ProductCategory.External_Id__c;
            Database.upsert(categoriesToUpsert, externalIdField, true);
        }
        
        Map<String, Id> categoryMap = new Map<String, Id>();
        for (ProductCategory pc : [SELECT Id, External_Id__c FROM ProductCategory WHERE CatalogId = :catalogId]) {
            categoryMap.put(pc.External_Id__c, pc.Id);
        }
        
        List<Object> productsJson = (List<Object>) JSON.deserializeUntyped(prodResponse.getBody());
        List<Product2> productsToUpsert = new List<Product2>();
        
        List<String> extIds = new List<String>();
        for (Object obj : productsJson) {
            Map<String, Object> prodMap = (Map<String, Object>) obj;
            extIds.add(String.valueOf(prodMap.get('id')));
        }
        
        // Query to match existing products based on External ID to perform updates on match
        Map<String, Product2> existingProductMap = new Map<String, Product2>();
        for (Product2 p : [SELECT Id, ExternalId FROM Product2 WHERE ExternalId IN :extIds]) {
            existingProductMap.put(p.ExternalId, p);
        }
        
        for (Object obj : productsJson) {
            Map<String, Object> prodMap = (Map<String, Object>) obj;
            String prodId = String.valueOf(prodMap.get('id'));
            String title = (String) prodMap.get('title');
            Decimal price = Decimal.valueOf(String.valueOf(prodMap.get('price')));
            String descr = (String) prodMap.get('description');
            
            List<Object> imagesObj = (List<Object>) prodMap.get('images');
            String imageUrl = '';
            if (imagesObj != null && !imagesObj.isEmpty()) {
                imageUrl = String.valueOf(imagesObj[0]);
                // Clean image URL formatting strings if parsed with array brackets
                if (imageUrl.startsWith('["') && imageUrl.endsWith('"]')) {
                    imageUrl = imageUrl.substring(2, imageUrl.length() - 2);
                } else if (imageUrl.startsWith('["')) {
                    imageUrl = imageUrl.substring(2);
                } else if (imageUrl.endsWith('"]')) {
                    imageUrl = imageUrl.substring(0, imageUrl.length() - 2);
                }
            }
            
            Map<String, Object> pCatMap = (Map<String, Object>) prodMap.get('category');
            String catExternalId = '';
            String catName = '';
            if (pCatMap != null) {
                catExternalId = String.valueOf(pCatMap.get('id'));
                catName = (String) pCatMap.get('name');
            }
            
            Product2 p = new Product2(
                Name = title,
                Description = descr,
                ExternalId = prodId,
                Fake_Store_Price__c = price,
                Fake_Store_Image_URL__c = imageUrl,
                Fake_Store_Category_Id__c = catExternalId,
                Fake_Store_Category_Name__c = catName,
                IsActive = true,
                Status__c = 'Active'
            );
            
            // Assign Id if the product already exists so it triggers update (saves query limits)
            if (existingProductMap.containsKey(prodId)) {
                p.Id = existingProductMap.get(prodId).Id;
            }
            
            if (categoryMap.containsKey(catExternalId)) {
                p.Category__c = categoryMap.get(catExternalId);
            }
            
            productsToUpsert.add(p);
        }
        
        if (!productsToUpsert.isEmpty()) {
            upsert productsToUpsert;
        }
    }

    /**
     * Queueable class standard framework implement logic.
     * Async mode callout support parameter `Database.AllowsCallouts` trigger rules requirement wrapper.
     */
    public class BulkSyncQueueable implements Queueable, Database.AllowsCallouts {
        public void execute(QueueableContext context) {
            try {
                ProductSyncService.syncEscuelaProducts();
            } catch (Exception ex) {
                ErrorLogger.logException('Integration', 'Category/Product Bulk Sync', ex);
                throw ex; // Re-throw to fail the Apex Job status
            }
        }
    }
}
