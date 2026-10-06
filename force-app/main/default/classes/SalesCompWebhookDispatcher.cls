public with sharing class SalesCompWebhookDispatcher implements Queueable, Database.AllowsCallouts {
    private static final List<Integer> RETRY_DELAYS_SECONDS = new List<Integer>{ 30, 120, 600, 1800, 7200 };

    private Id compensationId;

    public SalesCompWebhookDispatcher(Id compensationId) {
        this.compensationId = compensationId;
    }

    public void execute(QueueableContext context) {
        List<Sales_Compensation__c> records = [
            SELECT
                Id,
                Name,
                Transaction_Id__c,
                Event_Type__c,
                Status__c,
                Webhook_Status__c,
                Sales_Rep_Id__c,
                Sales_Rep_External_Id__c,
                Source_Opportunity_Id__c,
                Opportunity_External_Id__c,
                Compensation_Plan_Id__c,
                Compensation_Plan_Version__c,
                Currency_Code__c,
                Eligible_Amount__c,
                Commission_Rate__c,
                Commission_Amount__c,
                Accelerator__c,
                Final_Commission_Amount__c,
                Period_Type__c,
                Period_Start_Date__c,
                Period_End_Date__c,
                Webhook_Event_Id__c,
                Webhook_Payload__c,
                Webhook_Attempt_Count__c
            FROM Sales_Compensation__c
            WHERE Id = :compensationId
            LIMIT 1
        ];
        if (records.isEmpty()) {
            return;
        }

        Sales_Compensation__c compensation = records[0];
        if (compensation.Webhook_Status__c == 'DELIVERED') {
            return;
        }

        Integer attemptNumber = currentAttemptCount(compensation) + 1;
        SalesCompConfig.Settings settings = SalesCompConfig.get();

        try {
            if (!settings.active) {
                throw new SalesCompWebhookException('Sales compensation integration is not active.');
            }
            if (String.isBlank(settings.webhookEndpoint)) {
                throw new SalesCompWebhookException('Webhook endpoint is not configured.');
            }
            if (String.isBlank(settings.webhookSharedSecret)) {
                throw new SalesCompWebhookException('Webhook shared secret is not configured.');
            }

            String payload = String.isBlank(compensation.Webhook_Payload__c)
                ? SalesCompWebhookService.buildPayloadJson(compensation)
                : compensation.Webhook_Payload__c;

            HttpRequest request = new HttpRequest();
            request.setEndpoint(settings.webhookEndpoint);
            request.setMethod('POST');
            request.setHeader('Content-Type', 'application/json');
            request.setHeader('Idempotency-Key', compensation.Webhook_Event_Id__c);
            request.setHeader(
                'X-Compensation-Signature',
                SalesCompWebhookService.sign(payload, settings.webhookSharedSecret)
            );
            request.setTimeout(10000);
            request.setBody(payload);

            HttpResponse response = new Http().send(request);
            Integer statusCode = response.getStatusCode();
            if (statusCode >= 200 && statusCode < 300) {
                markDelivered(compensation, attemptNumber, statusCode, response.getBody());
            } else {
                markRetryOrFailed(
                    compensation,
                    attemptNumber,
                    settings,
                    statusCode,
                    response.getBody(),
                    'Webhook recipient returned HTTP ' + statusCode + '.'
                );
            }
        } catch (Exception ex) {
            markRetryOrFailed(compensation, attemptNumber, settings, null, null, ex.getMessage());
        }
    }

    private static void markDelivered(
        Sales_Compensation__c compensation,
        Integer attemptNumber,
        Integer statusCode,
        String responseBody
    ) {
        compensation.Webhook_Status__c = 'DELIVERED';
        compensation.Webhook_Attempt_Count__c = attemptNumber;
        compensation.Last_Webhook_Attempt_At__c = System.now();
        compensation.Next_Webhook_Attempt_At__c = null;
        compensation.Last_Webhook_Response_Code__c = statusCode;
        compensation.Last_Webhook_Response__c = truncate(responseBody, 32768);
        compensation.Error_Message__c = null;
        update compensation;
    }

    private static void markRetryOrFailed(
        Sales_Compensation__c compensation,
        Integer attemptNumber,
        SalesCompConfig.Settings settings,
        Integer statusCode,
        String responseBody,
        String errorMessage
    ) {
        DateTime nowValue = System.now();
        compensation.Webhook_Attempt_Count__c = attemptNumber;
        compensation.Last_Webhook_Attempt_At__c = nowValue;
        compensation.Last_Webhook_Response_Code__c = statusCode;
        compensation.Last_Webhook_Response__c = truncate(responseBody, 32768);
        compensation.Error_Message__c = truncate(errorMessage, 32768);

        if (attemptNumber >= settings.maxWebhookAttempts) {
            compensation.Webhook_Status__c = 'FAILED';
            compensation.Next_Webhook_Attempt_At__c = null;
        } else {
            compensation.Webhook_Status__c = 'RETRYING';
            compensation.Next_Webhook_Attempt_At__c = nowValue.addSeconds(delayAfterAttempt(attemptNumber));
        }

        update compensation;
    }

    private static Integer delayAfterAttempt(Integer attemptNumber) {
        Integer index = attemptNumber - 1;
        if (index < 0) {
            index = 0;
        }
        if (index >= RETRY_DELAYS_SECONDS.size()) {
            index = RETRY_DELAYS_SECONDS.size() - 1;
        }
        return RETRY_DELAYS_SECONDS[index];
    }

    private static Integer currentAttemptCount(Sales_Compensation__c compensation) {
        return compensation.Webhook_Attempt_Count__c == null
            ? 0
            : compensation.Webhook_Attempt_Count__c.intValue();
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }
}
