// ProductSyncEmailHandler: Inbound Email Service implementation class.
// Salesforce and third-party email system theke email ashle auto integration trigger run korbe.
// Trailhead Reference: "Inbound Email Services" (https://trailhead.salesforce.com/en/content/learn/modules/apex_integration_services/apex_integration_web_services)
public with sharing class ProductSyncEmailHandler implements Messaging.InboundEmailHandler {
    
    // Inbound emails check standard listener processing method
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        
        // System Log record load parameter setup 
        System_Log__c log = new System_Log__c();
        log.Log_Level__c = 'Info';
        log.Log_Type__c = 'Inbound Email';
        log.Event_Name__c = String.isNotBlank(email.subject) ? email.subject : 'No Subject';
        log.Automation_Name__c = 'ProductSyncEmailHandler';
        log.Source_Email__c = email.fromAddress;
        log.Imported_On__c = System.now();
        
        try {
            // Email ashle automatic category/product sync process queue run korbe
            System.enqueueJob(new ProductSyncService.BulkSyncQueueable());
            log.Status__c = 'Success';
            log.Message__c = 'Enqueued ProductSyncQueueable successfully from inbound email.';
            result.success = true;
        } catch (Exception e) {
            log.Log_Level__c = 'Error';
            log.Status__c = 'Failed';
            log.Message__c = 'Failed to enqueue ProductSyncQueueable: ' + e.getMessage() + '\nStack: ' + e.getStackTraceString();
            result.success = false;
        }
        
        insert log;
        return result;
    }
}
