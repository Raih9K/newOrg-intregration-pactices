public with sharing class ProductExternalUpdateQueueable implements Queueable, Database.AllowsCallouts {
    
    private List<Id> productIds;
    
    public ProductExternalUpdateQueueable(List<Id> ids) {
        this.productIds = ids;
    }
    
    public void execute(QueueableContext context) {
        if (productIds == null || productIds.isEmpty()) {
            return;
        }
        
        List<Product2> products = [
            SELECT Id, Name, Description, ExternalId, Price__c, Fake_Store_Price__c, 
                   Fake_Store_Image_URL__c, Category__c, Category__r.External_Id__c 
            FROM Product2 
            WHERE Id IN :productIds
        ];
        
        String token = ProductSyncService.getAccessToken();
        List<Product2> productsToUpdate = new List<Product2>();
        
        for (Product2 p : products) {
            try {
                Http http = new Http();
                HttpRequest req = new HttpRequest();
                req.setHeader('Authorization', 'Bearer ' + token);
                req.setHeader('Content-Type', 'application/json');
                
                Decimal priceVal = p.Price__c != null ? p.Price__c : (p.Fake_Store_Price__c != null ? p.Fake_Store_Price__c : 0);
                if (priceVal <= 0) {
                    priceVal = 1;
                }
                Integer categoryIdVal = 1;
                if (p.Category__c != null && String.isNotBlank(p.Category__r.External_Id__c)) {
                    try {
                        categoryIdVal = Integer.valueOf(p.Category__r.External_Id__c);
                    } catch (Exception ex) {
                        // ignore and use default
                    }
                }
                
                List<String> images = new List<String>();
                if (String.isNotBlank(p.Fake_Store_Image_URL__c)) {
                    images.add(p.Fake_Store_Image_URL__c);
                } else {
                    images.add('https://placehold.co/600x400');
                }
                
                Map<String, Object> payload = new Map<String, Object>{
                    'title' => p.Name,
                    'price' => priceVal,
                    'description' => String.isNotBlank(p.Description) ? p.Description : p.Name,
                    'categoryId' => categoryIdVal,
                    'images' => images
                };
                
                req.setBody(JSON.serialize(payload));
                
                if (String.isBlank(p.ExternalId)) {
                    req.setEndpoint('https://api.escuelajs.co/api/v1/products');
                    req.setMethod('POST');
                    HttpResponse res = http.send(req);
                    Integer postStatus = res.getStatusCode();
                    String postBody = res.getBody();
                    
                    if (postStatus == 200 || postStatus == 201) {
                        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(postBody);
                        String extId = String.valueOf(responseMap.get('id'));
                        productsToUpdate.add(new Product2(Id = p.Id, ExternalId = extId));
                        ErrorLogger.logInfo('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')', 'Successfully created product with External ID: ' + extId, postBody);
                    } else if (postStatus == 400) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'POST failed — Bad Request (400): Payload validation failed. Check required fields (title, price, categoryId, images).', postBody);
                    } else if (postStatus == 401) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'POST failed — Unauthorized (401): Access token is missing or expired.', postBody);
                    } else if (postStatus == 404) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'POST failed — Not Found (404): The endpoint URL may be incorrect.', postBody);
                    } else if (postStatus == 429) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'POST failed — Too Many Requests (429): API rate limit exceeded.', postBody);
                    } else if (postStatus >= 500) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'POST failed — Server Error (' + postStatus + '): 3rd party API internal error.', postBody);
                    } else {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'POST failed — Unexpected status (' + postStatus + '): ' + res.getStatus(), postBody);
                    }
                } else {
                    req.setEndpoint('https://api.escuelajs.co/api/v1/products/' + p.ExternalId);
                    req.setMethod('PUT');
                    HttpResponse res = http.send(req);
                    Integer putStatus = res.getStatusCode();
                    String putBody = res.getBody();
                    
                    if (putStatus == 200 || putStatus == 201) {
                        ErrorLogger.logInfo('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')', 'Successfully updated product on 3rd Party API', putBody);
                    } else if (putStatus == 400) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'PUT failed — Bad Request (400): Payload validation failed. Check required fields (title, price, categoryId, images).', putBody);
                    } else if (putStatus == 401) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'PUT failed — Unauthorized (401): Access token is missing or expired.', putBody);
                    } else if (putStatus == 404) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'PUT failed — Not Found (404): External ID "' + p.ExternalId + '" does not exist on 3rd party.', putBody);
                    } else if (putStatus == 429) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'PUT failed — Too Many Requests (429): API rate limit exceeded.', putBody);
                    } else if (putStatus >= 500) {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'PUT failed — Server Error (' + putStatus + '): 3rd party API internal error.', putBody);
                    } else {
                        ErrorLogger.logError('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')',
                            'PUT failed — Unexpected status (' + putStatus + '): ' + res.getStatus(), putBody);
                    }
                }

            } catch (Exception e) {
                ErrorLogger.logException('Integration', 'Product Outbound Sync (ID: ' + p.Id + ')', e);
            }
        }
        
        if (!productsToUpdate.isEmpty()) {
            update productsToUpdate;
        }
    }
}
