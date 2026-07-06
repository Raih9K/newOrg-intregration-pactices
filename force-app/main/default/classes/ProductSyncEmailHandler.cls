public with sharing class ProductSyncEmailHandler implements Messaging.InboundEmailHandler {
    public Messaging.InboundEmailResult handleInboundEmail(Messaging.InboundEmail email, Messaging.InboundEnvelope envelope) {
        Messaging.InboundEmailResult result = new Messaging.InboundEmailResult();
        
        System_Log__c log = new System_Log__c();
        log.Log_Level__c = 'Info';
        log.Log_Type__c = 'Inbound Email';
        log.Event_Name__c = String.isNotBlank(email.subject) ? email.subject : 'No Subject';
        log.Automation_Name__c = 'ProductSyncEmailHandler';
        log.Source_Email__c = email.fromAddress;
        log.Imported_On__c = System.now();
        
        try {
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
