global with sharing class SalesCompWebhookRetryScheduler implements Schedulable {
    global void execute(SchedulableContext context) {
        SalesCompConfig.Settings settings = SalesCompConfig.get();
        if (!settings.active) {
            return;
        }

        Integer maxAttempts = settings.maxWebhookAttempts;
        DateTime nowValue = System.now();
        for (Sales_Compensation__c compensation : [
            SELECT Id
            FROM Sales_Compensation__c
            WHERE Webhook_Status__c IN ('PENDING', 'RETRYING')
                AND Next_Webhook_Attempt_At__c <= :nowValue
                AND Webhook_Attempt_Count__c < :maxAttempts
            LIMIT 50
        ]) {
            System.enqueueJob(new SalesCompWebhookDispatcher(compensation.Id));
        }
    }

    public static String scheduleEveryMinute() {
        return System.schedule(
            'Sales Compensation Webhook Retry',
            '0 0/1 * * * ?',
            new SalesCompWebhookRetryScheduler()
        );
    }
}
