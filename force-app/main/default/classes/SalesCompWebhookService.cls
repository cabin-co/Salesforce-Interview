public with sharing class SalesCompWebhookService {
    public static String buildEventId(Sales_Compensation__c compensation) {
        return 'EVT-' + (String.isBlank(compensation.Name) ? String.valueOf(compensation.Id) : compensation.Name);
    }

    public static String buildPayloadJson(Sales_Compensation__c compensation) {
        SalesCompConfig.Settings settings = SalesCompConfig.get();

        Map<String, Object> payload = new Map<String, Object>{
            'eventId' => compensation.Webhook_Event_Id__c,
            'eventType' => 'COMPENSATION_CALCULATED',
            'eventVersion' => settings.webhookEventVersion,
            'occurredAt' => formatDatetime(System.now()),
            'compensation' => new Map<String, Object>{
                'id' => compensation.Name,
                'status' => compensation.Status__c,
                'transaction' => new Map<String, Object>{
                    'id' => compensation.Transaction_Id__c,
                    'type' => compensation.Event_Type__c
                },
                'salesRep' => new Map<String, Object>{
                    'id' => compensation.Sales_Rep_Id__c,
                    'externalId' => compensation.Sales_Rep_External_Id__c
                },
                'opportunity' => new Map<String, Object>{
                    'id' => compensation.Source_Opportunity_Id__c,
                    'externalId' => compensation.Opportunity_External_Id__c
                },
                'compensationPlan' => new Map<String, Object>{
                    'id' => compensation.Compensation_Plan_Id__c,
                    'version' => compensation.Compensation_Plan_Version__c
                },
                'calculation' => new Map<String, Object>{
                    'currency' => compensation.Currency_Code__c,
                    'eligibleAmount' => compensation.Eligible_Amount__c,
                    'commissionRate' => compensation.Commission_Rate__c,
                    'commissionAmount' => compensation.Commission_Amount__c,
                    'accelerator' => compensation.Accelerator__c,
                    'finalCommissionAmount' => compensation.Final_Commission_Amount__c
                },
                'period' => new Map<String, Object>{
                    'type' => compensation.Period_Type__c,
                    'startDate' => formatDate(compensation.Period_Start_Date__c),
                    'endDate' => formatDate(compensation.Period_End_Date__c)
                }
            }
        };

        return JSON.serialize(payload);
    }

    public static String sign(String rawBody, String sharedSecret) {
        String body = rawBody == null ? '' : rawBody;
        String secret = sharedSecret == null ? '' : sharedSecret;
        Blob mac = Crypto.generateMac('HmacSHA256', Blob.valueOf(body), Blob.valueOf(secret));
        return 'sha256=' + EncodingUtil.convertToHex(mac).toLowerCase();
    }

    public static Boolean isValidSignature(String rawBody, String sharedSecret, String signatureHeader) {
        if (String.isBlank(signatureHeader) || !signatureHeader.startsWith('sha256=')) {
            return false;
        }
        return secureEquals(sign(rawBody, sharedSecret), signatureHeader.trim());
    }

    private static Boolean secureEquals(String expected, String supplied) {
        if (String.isBlank(expected) || String.isBlank(supplied)) {
            return false;
        }
        String expectedDigest = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(expected))
        );
        String suppliedDigest = EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(supplied))
        );
        return expectedDigest == suppliedDigest;
    }

    private static String formatDatetime(Datetime value) {
        return value == null ? null : value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static String formatDate(Date value) {
        return value == null
            ? null
            : String.valueOf(value.year()) + '-' + twoDigits(value.month()) + '-' + twoDigits(value.day());
    }

    private static String twoDigits(Integer value) {
        return value < 10 ? '0' + String.valueOf(value) : String.valueOf(value);
    }
}
