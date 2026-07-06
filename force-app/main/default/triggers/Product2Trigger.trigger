trigger Product2Trigger on Product2 (before update, after update) {
    Product2TriggerHandler handler = new Product2TriggerHandler();
    if (Trigger.isBefore && Trigger.isUpdate) {
        handler.onBeforeUpdate(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isAfter && Trigger.isUpdate) {
        handler.onAfterUpdate(Trigger.new, Trigger.oldMap);
    }
}
