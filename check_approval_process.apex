// Find or create an Active product
List<Product2> prods = [SELECT Id, Name, Status__c, Proposed_Changes__c, IsActive, Price__c, QC_Approver__c FROM Product2 WHERE (Status__c = 'Active' OR IsActive = true) AND QC_Approver__c != null LIMIT 1];
if (prods.isEmpty()) {
    System.debug('Creating dummy product and setting up QC Approver');
    // Ensure we have a Group member and user to set as QC Approver
    Group gp = [SELECT Id FROM Group WHERE DeveloperName = 'Product_QC_Group' LIMIT 1];
    GroupMember gm = [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :gp.Id LIMIT 1];
    
    Product2 p = new Product2(
        Name = 'Test Life Cycle Product',
        IsActive = true,
        Status__c = 'Active',
        Price__c = 100
    );
    insert p;
    prods.add(p);
}

Product2 prod = prods[0];
System.debug('Initial Product: ' + prod.Name + ' | Status: ' + prod.Status__c + ' | Price: ' + prod.Price__c);

// Edit the product
prod.Name = 'Life Cycle Product Edited Name';
prod.Price__c = 250;
update prod;

// Query to see if it is Under Verify and submitted for approval
Product2 editedProd = [SELECT Id, Name, Status__c, Proposed_Changes__c, QC_Approver__c FROM Product2 WHERE Id = :prod.Id];
System.debug('After Edit Product: ' + editedProd.Name + ' | Status: ' + editedProd.Status__c + ' | Proposed: ' + editedProd.Proposed_Changes__c);

// Check if there is a pending approval work item
List<ProcessInstanceWorkitem> workItems = [
    SELECT Id, ProcessInstance.TargetObjectId 
    FROM ProcessInstanceWorkitem 
    WHERE ProcessInstance.TargetObjectId = :prod.Id
];

if (!workItems.isEmpty()) {
    System.debug('Found pending approval request! Approving it now...');
    Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
    req.setComments('Approving via test script');
    req.setAction('Approve');
    req.setWorkitemId(workItems[0].Id);
    Approval.ProcessResult result = Approval.process(req);
    System.debug('Approval success: ' + result.isSuccess());
    
    // Check final state
    Product2 finalProd = [SELECT Id, Name, Status__c, Proposed_Changes__c, Price__c FROM Product2 WHERE Id = :prod.Id];
    System.debug('Final Approved Product: ' + finalProd.Name + ' | Status: ' + finalProd.Status__c + ' | Price: ' + finalProd.Price__c + ' | Proposed: ' + finalProd.Proposed_Changes__c);
} else {
    System.debug('ERROR: No pending approval work item found!');
}
