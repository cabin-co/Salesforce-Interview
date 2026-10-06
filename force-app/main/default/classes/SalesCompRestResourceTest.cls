@IsTest
private class SalesCompRestResourceTest {
    @IsTest
    static void acceptsClosedWonRequestAndDeliversWebhook() {
        configureIntegration();
        Test.setMock(HttpCalloutMock.class, new SuccessWebhookMock());

        Test.startTest();
        Map<String, Object> response = invoke(validPayload('TXN-2026-000184'), 'TXN-2026-000184', 'test-api-key');
        Test.stopTest();

        System.assertEquals(202, RestContext.response.statusCode);
        System.assertEquals('TXN-2026-000184', response.get('transactionId'));
        System.assertEquals('ACCEPTED', response.get('status'));
        System.assertEquals('PENDING', response.get('webhookStatus'));

        Sales_Compensation__c compensation = [
            SELECT
                Name,
                Transaction_Id__c,
                Webhook_Status__c,
                Webhook_Attempt_Count__c,
                Eligible_Amount__c,
                Commission_Rate__c,
                Commission_Amount__c,
                Final_Commission_Amount__c,
                Period_Start_Date__c,
                Period_End_Date__c
            FROM Sales_Compensation__c
            WHERE Transaction_Id__c = 'TXN-2026-000184'
            LIMIT 1
        ];
        System.assertEquals('DELIVERED', compensation.Webhook_Status__c);
        System.assertEquals(Decimal.valueOf(1), compensation.Webhook_Attempt_Count__c);
        System.assertEquals(Decimal.valueOf('125000.00'), compensation.Eligible_Amount__c);
        System.assertEquals(Decimal.valueOf('0.1000'), compensation.Commission_Rate__c);
        System.assertEquals(Decimal.valueOf('12500.00'), compensation.Commission_Amount__c);
        System.assertEquals(Decimal.valueOf('12500.00'), compensation.Final_Commission_Amount__c);
        System.assertEquals(Date.newInstance(2026, 10, 1), compensation.Period_Start_Date__c);
        System.assertEquals(Date.newInstance(2026, 10, 31), compensation.Period_End_Date__c);
        System.assertEquals(
            2,
            [SELECT COUNT() FROM Sales_Comp_Product__c WHERE Compensation__c = :compensation.Id]
        );
    }

    @IsTest
    static void rejectsUnauthorizedRequest() {
        configureIntegration();

        Test.startTest();
        Map<String, Object> response = invoke(validPayload('TXN-UNAUTH'), 'TXN-UNAUTH', 'wrong-key');
        Test.stopTest();

        System.assertEquals(401, RestContext.response.statusCode);
        Map<String, Object> error = (Map<String, Object>) response.get('error');
        System.assertEquals('UNAUTHORIZED', error.get('code'));
        System.assertEquals(0, [SELECT COUNT() FROM Sales_Compensation__c]);
    }

    @IsTest
    static void rejectsInvalidPayload() {
        configureIntegration();

        Test.startTest();
        Map<String, Object> response = invoke('{}', 'BAD-PAYLOAD', 'test-api-key');
        Test.stopTest();

        System.assertEquals(400, RestContext.response.statusCode);
        Map<String, Object> error = (Map<String, Object>) response.get('error');
        System.assertEquals('VALIDATION_ERROR', error.get('code'));
        System.assertEquals(0, [SELECT COUNT() FROM Sales_Compensation__c]);
    }

    @IsTest
    static void rejectsDuplicateIdempotencyKey() {
        configureIntegration();
        Test.setMock(HttpCalloutMock.class, new SuccessWebhookMock());

        Test.startTest();
        invoke(validPayload('TXN-DUPLICATE'), 'IDEMPOTENCY-DUPLICATE', 'test-api-key');
        Map<String, Object> secondResponse = invoke(
            validPayload('TXN-DUPLICATE'),
            'IDEMPOTENCY-DUPLICATE',
            'test-api-key'
        );
        Test.stopTest();

        System.assertEquals(409, RestContext.response.statusCode);
        Map<String, Object> error = (Map<String, Object>) secondResponse.get('error');
        System.assertEquals('DUPLICATE_TRANSACTION', error.get('code'));
        System.assertEquals(1, [SELECT COUNT() FROM Sales_Compensation__c WHERE Transaction_Id__c = 'TXN-DUPLICATE']);
    }

    @IsTest
    static void schedulesRetryWhenWebhookFails() {
        configureIntegration();
        Test.setMock(HttpCalloutMock.class, new FailingWebhookMock());

        Test.startTest();
        invoke(validPayload('TXN-WEBHOOK-FAIL'), 'TXN-WEBHOOK-FAIL', 'test-api-key');
        Test.stopTest();

        Sales_Compensation__c compensation = [
            SELECT
                Webhook_Status__c,
                Webhook_Attempt_Count__c,
                Last_Webhook_Response_Code__c,
                Next_Webhook_Attempt_At__c,
                Error_Message__c
            FROM Sales_Compensation__c
            WHERE Transaction_Id__c = 'TXN-WEBHOOK-FAIL'
            LIMIT 1
        ];
        System.assertEquals('RETRYING', compensation.Webhook_Status__c);
        System.assertEquals(Decimal.valueOf(1), compensation.Webhook_Attempt_Count__c);
        System.assertEquals(Decimal.valueOf(500), compensation.Last_Webhook_Response_Code__c);
        System.assertNotEquals(null, compensation.Next_Webhook_Attempt_At__c);
        System.assert(compensation.Error_Message__c.contains('HTTP 500'));
    }

    @IsTest
    static void validatesWebhookSignature() {
        String payload = '{"received":true,"eventId":"EVT-1"}';
        String signature = SalesCompWebhookService.sign(payload, 'shared-secret');

        System.assert(SalesCompWebhookService.isValidSignature(payload, 'shared-secret', signature));
        System.assert(!SalesCompWebhookService.isValidSignature(payload, 'wrong-secret', signature));
        System.assert(!SalesCompWebhookService.isValidSignature(payload, 'shared-secret', 'sha256=bad'));
    }

    private static void configureIntegration() {
        SalesCompConfig.Settings settings = new SalesCompConfig.Settings();
        settings.active = true;
        settings.apiKey = 'test-api-key';
        settings.webhookEndpoint = 'https://crm.example.com/api/webhooks/sales-compensation';
        settings.webhookSharedSecret = 'test-webhook-secret';
        settings.webhookEventVersion = '1.0';
        settings.maxWebhookAttempts = 6;
        SalesCompConfig.testSettings = settings;

        SalesCompCommissionRateProvider.testRates = new Map<String, Decimal>{
            'ACCOUNT_EXECUTIVE' => 0.10,
            'SALES_DEVELOPMENT_REP' => 0.05,
            'ACCOUNT_MANAGER' => 0.07,
            'SALES_MANAGER' => 0.03
        };
    }

    private static Map<String, Object> invoke(String body, String idempotencyKey, String apiKey) {
        RestRequest request = new RestRequest();
        request.requestUri = '/services/apexrest/api/v1/compensation/calculate';
        request.httpMethod = 'POST';
        request.requestBody = Blob.valueOf(body);
        request.addHeader('Content-Type', 'application/json');
        if (apiKey != null) {
            request.addHeader('Authorization', 'Bearer ' + apiKey);
        }
        if (idempotencyKey != null) {
            request.addHeader('Idempotency-Key', idempotencyKey);
        }

        RestContext.request = request;
        RestContext.response = new RestResponse();
        SalesCompRestResource.doPost();
        return (Map<String, Object>) JSON.deserializeUntyped(RestContext.response.responseBody.toString());
    }

    private static String validPayload(String transactionId) {
        Map<String, Object> payload = new Map<String, Object>();
        payload.put('transactionId', transactionId);
        payload.put('eventType', 'OPPORTUNITY_CLOSED_WON');
        payload.put('occurredAt', '2026-10-06T17:30:00Z');
        payload.put(
            'salesRep',
            new Map<String, Object>{
                'id' => '0058A000001ABCQ',
                'externalId' => 'REP-10482',
                'firstName' => 'Jane',
                'lastName' => 'Smith',
                'email' => 'jane.smith@example.com',
                'role' => 'ACCOUNT_EXECUTIVE',
                'region' => 'WEST'
            }
        );
        payload.put(
            'opportunity',
            new Map<String, Object>{
                'id' => '0068A000002XYZQ',
                'externalId' => 'OPP-2026-9182',
                'name' => 'Acme Corporation - Enterprise Agreement',
                'stage' => 'CLOSED_WON',
                'closeDate' => '2026-10-06',
                'currency' => 'USD',
                'amount' => 125000.00,
                'account' => new Map<String, Object>{ 'id' => '0018A000004LMNQ', 'name' => 'Acme Corporation' }
            }
        );
        payload.put('compensationPlan', new Map<String, Object>{ 'id' => 'PLAN-AE-2026', 'version' => 3 });
        payload.put(
            'products',
            new List<Object>{
                new Map<String, Object>{
                    'productId' => 'PROD-ENT-001',
                    'productName' => 'Enterprise Platform',
                    'quantity' => 1,
                    'unitPrice' => 100000.00,
                    'amount' => 100000.00
                },
                new Map<String, Object>{
                    'productId' => 'PROD-SVC-001',
                    'productName' => 'Professional Services',
                    'quantity' => 1,
                    'unitPrice' => 25000.00,
                    'amount' => 25000.00
                }
            }
        );
        return JSON.serialize(payload);
    }

    private class SuccessWebhookMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            System.assertEquals('POST', request.getMethod());
            System.assertEquals('application/json', request.getHeader('Content-Type'));
            System.assert(request.getHeader('X-Compensation-Signature').startsWith('sha256='));
            System.assert(request.getBody().contains('COMPENSATION_CALCULATED'));

            HttpResponse response = new HttpResponse();
            response.setStatusCode(200);
            response.setHeader('Content-Type', 'application/json');
            response.setBody('{"received":true}');
            return response;
        }
    }

    private class FailingWebhookMock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest request) {
            HttpResponse response = new HttpResponse();
            response.setStatusCode(500);
            response.setBody('{"received":false}');
            return response;
        }
    }
}
