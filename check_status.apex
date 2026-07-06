Product2 prod = [SELECT Id, Name, Status__c, Proposed_Changes__c, IsActive FROM Product2 WHERE Status__c = 'Active' OR IsActive = true LIMIT 1];
if (prod != null) {
    prod.Status__c = 'Active'; // Ensure it's active
    update prod; // To reset state if needed
    
    prod.Name = prod.Name + ' (Edited)';
    update prod;
    
    Product2 updatedProd = [SELECT Id, Name, Status__c, Proposed_Changes__c, QC_Approver__c FROM Product2 WHERE Id = :prod.Id];
    System.debug('UPDATED PROD STATUS: ' + updatedProd.Status__c);
    System.debug('UPDATED PROD NAME: ' + updatedProd.Name);
    System.debug('PROPOSED CHANGES: ' + updatedProd.Proposed_Changes__c);
    System.debug('QC APPROVER: ' + updatedProd.QC_Approver__c);
} else {
    System.debug('NO ACTIVE PRODUCT FOUND');
}
