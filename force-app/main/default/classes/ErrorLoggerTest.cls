@isTest
public class ErrorLoggerTest {
    @isTest
    static void testLogging() {
        Test.startTest();
        ErrorLogger.logError('Integration', 'Sync Failure', 'Error message details', 'Payload data');
        ErrorLogger.logInfo('Integration', 'Sync Success', 'Info message details', 'Payload data');
        
        try {
            Integer i = 0;
            Integer result = 10 / i;
        } catch (Exception ex) {
            ErrorLogger.logException('Apex Exception', 'Calculation Error', ex);
        }
        Test.stopTest();
        
        List<System_Log__c> logs = [SELECT Log_Type__c, Event_Name__c, Message__c, Log_Level__c FROM System_Log__c];
        System.assertEquals(3, logs.size(), 'Three log records should be inserted');
    }

    @isTest
    static void testFlowLogging() {
        ErrorLogger.LogRequest req = new ErrorLogger.LogRequest();
        req.logType = 'Flow';
        req.eventName = 'Test Flow Error';
        req.message = 'Something went wrong in the Flow';
        req.payload = 'Fault: Some fault message';
        req.logLevel = 'ERROR';
        req.status = 'Failed';

        Test.startTest();
        ErrorLogger.logErrorFromFlow(new List<ErrorLogger.LogRequest>{ req });
        Test.stopTest();

        List<System_Log__c> logs = [SELECT Log_Type__c, Event_Name__c, Message__c, Log_Level__c FROM System_Log__c WHERE Log_Type__c = 'Flow'];
        System.assertEquals(1, logs.size(), 'One Flow log record should be inserted');
        System.assertEquals('Test Flow Error', logs[0].Event_Name__c);
    }
}
