public with sharing class ProductListSyncController {

    /**
     * AuraEnabled: Triggered from LWC button — enqueues a full bulk product sync.
     */
    @AuraEnabled
    public static void runManualSync() {
        try {
            System.enqueueJob(new ProductSyncService.BulkSyncQueueable());
        } catch (Exception e) {
            ErrorLogger.logException('Integration', 'All Products Queueable Sync Trigger', e);
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * InvocableMethod: Triggered from Salesforce Flow — enqueues a full bulk product sync.
     * Replaces the standalone ERP_ProductSyncInvocable class.
     */
    @InvocableMethod(label='Run ERP Product Sync' description='Triggers the full product synchronisation from the external API. Use in Flow to schedule or event-trigger a bulk sync.')
    public static void runSyncFromFlow(List<Boolean> ignored) {
        System.enqueueJob(new ProductSyncService.BulkSyncQueueable());
    }

    /**
     * AuraEnabled: Triggered from LWC Quick Action — syncs a single product record to the 3rd party API in real time.
     */
    @AuraEnabled
    public static void syncSingleProduct(Id recordId) {
        try {
            Product2 p = [
                SELECT Id, Name, Description, ExternalId, Price__c, Fake_Store_Price__c, 
                       Fake_Store_Image_URL__c, Category__c, Category__r.External_Id__c 
                FROM Product2 
                WHERE Id = :recordId
            ];
            
            String token = ProductSyncService.getAccessToken();
            Http http = new Http();
            HttpRequest req = new HttpRequest();
            req.setHeader('Authorization', 'Bearer ' + token);
            req.setHeader('Content-Type', 'application/json');
            
            Decimal priceVal = p.Price__c != null ? p.Price__c : (p.Fake_Store_Price__c != null ? p.Fake_Store_Price__c : 0);
            if (priceVal <= 0) {
                throw new CalloutException('Product price must be a positive number (greater than 0) to sync to 3rd Party API. Please update the Price field.');
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
                
                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                    Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                    String extId = String.valueOf(responseMap.get('id'));
                    p.ExternalId = extId;
                    update p;
                    ErrorLogger.logInfo('Integration', 'Single Product Sync (ID: ' + recordId + ')', 'Successfully created product on 3rd Party API with External ID: ' + extId, res.getBody());
                } else {
                    throw new CalloutException('Failed to create product: ' + res.getStatus() + ' - ' + res.getBody());
                }
            } else {
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
