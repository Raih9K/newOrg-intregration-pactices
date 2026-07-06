public with sharing class ErrorLogger {
    
    /**
     * Logs an error message to the System_Log__c object.
     */
    public static void logError(String logType, String eventName, String message, String payload) {
        try {
            System_Log__c log = new System_Log__c(
                Log_Type__c = logType,
                Event_Name__c = eventName,
                Message__c = message != null && message.length() > 255 ? message.substring(0, 255) : message,
                Payload__c = payload,
                Log_Level__c = 'ERROR',
                Status__c = 'Failed'
            );
            insert log;
        } catch (Exception e) {
            System.debug('Failed to insert error log: ' + e.getMessage());
        }
    }

    /**
     * Logs an info message to the System_Log__c object.
     */
    public static void logInfo(String logType, String eventName, String message, String payload) {
        try {
            System_Log__c log = new System_Log__c(
                Log_Type__c = logType,
                Event_Name__c = eventName,
                Message__c = message != null && message.length() > 255 ? message.substring(0, 255) : message,
                Payload__c = payload,
                Log_Level__c = 'INFO',
                Status__c = 'Success'
            );
            insert log;
        } catch (Exception e) {
            System.debug('Failed to insert info log: ' + e.getMessage());
        }
    }

    /**
     * Logs a caught exception details to the System_Log__c object.
     */
    public static void logException(String logType, String eventName, Exception ex) {
        if (ex == null) return;
        String message = ex.getMessage();
        String payload = 'Exception Type: ' + ex.getTypeName() + '\n' +
                         'Stack Trace: ' + ex.getStackTraceString();
        logError(logType, eventName, message, payload);
    }
    
    /**
     * Invocable method to allow logging errors from Flows.
     */
    @InvocableMethod(label='Log Error' description='Logs an error or message to System_Log__c')
    public static void logErrorFromFlow(List<LogRequest> requests) {
        List<System_Log__c> logs = new List<System_Log__c>();
        for (LogRequest req : requests) {
            String msg = req.message != null && req.message.length() > 255 ? req.message.substring(0, 255) : req.message;
            logs.add(new System_Log__c(
                Log_Type__c = req.logType != null ? req.logType : 'Flow',
                Event_Name__c = req.eventName != null ? req.eventName : 'Flow Error',
                Message__c = msg,
                Payload__c = req.payload,
                Log_Level__c = req.logLevel != null ? req.logLevel : 'ERROR',
                Status__c = req.status != null ? req.status : 'Failed'
            ));
        }
        if (!logs.isEmpty()) {
            try {
                insert logs;
            } catch (Exception e) {
                System.debug('Failed to insert flow error log: ' + e.getMessage());
            }
        }
    }
    
    public class LogRequest {
        @InvocableVariable(label='Log Type' description='e.g., Integration, Flow' required=true)
        public String logType;
        
        @InvocableVariable(label='Event Name' description='Context of the event' required=true)
        public String eventName;
        
        @InvocableVariable(label='Message' description='Main error message (max 255 chars)' required=true)
        public String message;
        
        @InvocableVariable(label='Payload/Details' description='Detailed fault message or stack trace' required=false)
        public String payload;
        
        @InvocableVariable(label='Log Level' description='ERROR, INFO, etc.' required=false)
        public String logLevel;
        
        @InvocableVariable(label='Status' description='Success or Failed' required=false)
        public String status;
    }
}
