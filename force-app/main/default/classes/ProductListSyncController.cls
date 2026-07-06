// ProductListSyncController: Lightning Web Component (LWC) and Salesforce Flow control class.
// Ekhane visual buttons er calls validation and single-product-outbound calls handle kora hoy.
// Trailhead Reference: "Apex Integration Services" (https://trailhead.salesforce.com/content/learn/modules/apex_integration_services)
// "Lightning Web Component Basics" (https://trailhead.salesforce.com/content/learn/modules/lightning_web_components_basics)
public with sharing class ProductListSyncController {

    /**
     * AuraEnabled: LWC component er sync button theke directly trigger hoy.
     * Eta backend execution Queueable framework call queue block handle kore.
     */
    @AuraEnabled
    public static void runManualSync() {
        try {
            // Queue list execution bulk data processing enqueued trigger
            System.enqueueJob(new ProductSyncService.BulkSyncQueueable());
        } catch (Exception e) {
            // Error logger use kore log database e record kora hocche
            ErrorLogger.logException('Integration', 'All Products Queueable Sync Trigger', e);
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * InvocableMethod: Salesforce Screen/Autolaunched Flow or Process Builder context block theke flow trigger.
     */
    @InvocableMethod(label='Run ERP Product Sync' description='Triggers the full product synchronisation from the external API. Use in Flow to schedule or event-trigger a bulk sync.')
    public static void runSyncFromFlow(List<Boolean> ignored) {
        System.enqueueJob(new ProductSyncService.BulkSyncQueueable());
    }

    /**
     * AuraEnabled: LWC Single Product Quick Action theke record sync push call execution trigger.
     * Single record real-time push method external system products.
     */
    @AuraEnabled
    public static void syncSingleProduct(Id recordId) {
        try {
            // Salesforce database theke unique product query
            Product2 p = [
                SELECT Id, Name, Description, ExternalId, Price__c, Fake_Store_Price__c, 
                       Fake_Store_Image_URL__c, Category__c, Category__r.External_Id__c 
                FROM Product2 
                WHERE Id = :recordId
            ];
            
            // Authorization access token generate execution block
            String token = ProductSyncService.getAccessToken();
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setHeader('Authorization', 'Bearer ' + token);
            req.setHeader('Content-Type', 'application/json');
            
            // Price validate kora hocche positive number checking logic criteria
            Decimal priceVal = p.Price__c != null ? p.Price__c : (p.Fake_Store_Price__c != null ? p.Fake_Store_Price__c : 0);
            if (priceVal <= 0) {
                throw new CalloutException('Product price must be a positive number (greater than 0) to sync to 3rd Party API. Please update the Price field.');
            }
            
            // Category assign checks, fallbacks
            Integer categoryIdVal = 1;
            if (p.Category__c != null && String.isNotBlank(p.Category__r.External_Id__c)) {
                try {
                    categoryIdVal = Integer.valueOf(p.Category__r.External_Id__c);
                } catch (Exception ex) {
                    // parsing fail hole default category ID "1" load thakbe
                }
            }
            
            // Image URLs validation array list assignment
            List<String> images = new List<String>();
            if (String.isNotBlank(p.Fake_Store_Image_URL__c)) {
                images.add(p.Fake_Store_Image_URL__c);
            } else {
                images.add('https://placehold.co/600x400');
            }
            
            // Payload parameters map processing format json
            Map<String, Object> payload = new Map<String, Object>{
                'title' => p.Name,
                'price' => priceVal,
                'description' => String.isNotBlank(p.Description) ? p.Description : p.Name,
                'categoryId' => categoryIdVal,
                'images' => images
            };
            
            req.setBody(JSON.serialize(payload));
            
            // Product mapping create logic (External ID null context) vs update logic (External ID standard value present)
            if (String.isBlank(p.ExternalId)) {
                // Post validation logic API URL
                req.setEndpoint('https://api.escuelajs.co/api/v1/products');
                req.setMethod('POST');
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String extId = String.valueOf(responseMap.get('id'));
                    p.ExternalId = extId;
                    update p; // update external ID to Salesforce Product record
                    ErrorLogger.logInfo('Integration', 'Single Product Sync (ID: ' + recordId + ')', 'Successfully created product on 3rd Party API with External ID: ' + extId, res.getBody());
                } else {
                    throw new CalloutException('Failed to create product: ' + res.getStatus() + ' - ' + res.getBody());
                }
            } else {
                // Put validation logic update URL with External ID endpoint path segment
                req.setEndpoint('https://api.escuelajs.co/api/v1/products/' + p.ExternalId);
                req.setMethod('PUT');
                HttpResponse res = http.send(req);
                
                if (res.getStatusCode() != 200 && res.getStatusCode() != 201) {
                    throw new CalloutException('Failed to update product: ' + res.getStatus() + ' - ' + res.getBody());
                } else {
                    ErrorLogger.logInfo('Integration', 'Single Product Sync (ID: ' + recordId + ')', 'Successfully updated product on 3rd Party API', res.getBody());
                }
            }
        } catch (Exception e) {
            ErrorLogger.logException('Integration', 'Single Product Sync (ID: ' + recordId + ')', e);
            throw new AuraHandledException(e.getMessage());
        }
    }
}
