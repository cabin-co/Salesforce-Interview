public with sharing class SalesCompConfig {
    @TestVisible
    private static Settings testSettings;

    public class Settings {
        public Boolean active;
        public String apiKey;
        public String webhookEndpoint;
        public String webhookSharedSecret;
        public String webhookEventVersion;
        public Integer maxWebhookAttempts;

        public Settings() {
            active = false;
            webhookEventVersion = '1.0';
            maxWebhookAttempts = 6;
        }
    }

    public static Settings get() {
        if (testSettings != null) {
            return testSettings;
        }

        Settings settings = new Settings();
        List<Sales_Comp_Integration_Config__mdt> configs = [
            SELECT
                Active__c,
                Api_Key__c,
                Webhook_Endpoint__c,
                Webhook_Shared_Secret__c,
                Webhook_Event_Version__c,
                Max_Webhook_Attempts__c
            FROM Sales_Comp_Integration_Config__mdt
            WHERE DeveloperName = 'Default'
            LIMIT 1
        ];

        if (configs.isEmpty()) {
            return settings;
        }

        Sales_Comp_Integration_Config__mdt config = configs[0];
        settings.active = config.Active__c;
        settings.apiKey = config.Api_Key__c;
        settings.webhookEndpoint = config.Webhook_Endpoint__c;
        settings.webhookSharedSecret = config.Webhook_Shared_Secret__c;
        settings.webhookEventVersion = String.isBlank(config.Webhook_Event_Version__c)
            ? '1.0'
            : config.Webhook_Event_Version__c;

        if (config.Max_Webhook_Attempts__c != null) {
            Integer attempts = config.Max_Webhook_Attempts__c.intValue();
            settings.maxWebhookAttempts = attempts < 1 ? 1 : attempts;
        }

        return settings;
    }
}
