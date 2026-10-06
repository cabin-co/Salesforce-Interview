public with sharing class SalesCompCommissionRateProvider {
    @TestVisible
    private static Map<String, Decimal> testRates;

    private static final Map<String, Decimal> DEFAULT_RATES = new Map<String, Decimal>{
        'ACCOUNT_EXECUTIVE' => 0.10,
        'SALES_DEVELOPMENT_REP' => 0.05,
        'ACCOUNT_MANAGER' => 0.07,
        'SALES_MANAGER' => 0.03
    };

    public static Decimal rateFor(String salesRole) {
        if (String.isBlank(salesRole)) {
            return 0;
        }
        if (testRates != null && testRates.containsKey(salesRole)) {
            return testRates.get(salesRole);
        }

        List<Sales_Comp_Commission_Rate__mdt> configuredRates = [
            SELECT Commission_Rate__c
            FROM Sales_Comp_Commission_Rate__mdt
            WHERE Active__c = TRUE AND Sales_Role__c = :salesRole
            LIMIT 1
        ];
        if (!configuredRates.isEmpty() && configuredRates[0].Commission_Rate__c != null) {
            return configuredRates[0].Commission_Rate__c;
        }

        return DEFAULT_RATES.containsKey(salesRole) ? DEFAULT_RATES.get(salesRole) : 0;
    }
}
