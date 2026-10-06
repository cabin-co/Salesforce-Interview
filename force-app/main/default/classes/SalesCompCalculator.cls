public with sharing class SalesCompCalculator {
    public class CalculationResult {
        public Decimal eligibleAmount;
        public Decimal commissionRate;
        public Decimal commissionAmount;
        public Decimal accelerator;
        public Decimal finalCommissionAmount;
        public String periodType;
        public Date periodStartDate;
        public Date periodEndDate;
    }

    public static CalculationResult calculate(SalesCompRequest request) {
        CalculationResult result = new CalculationResult();
        result.commissionRate = SalesCompCommissionRateProvider.rateFor(request.salesRep.role);
        result.accelerator = 1.0;
        result.periodType = 'MONTH';
        result.periodStartDate = Date.newInstance(
            request.opportunity.closeDate.year(),
            request.opportunity.closeDate.month(),
            1
        );
        result.periodEndDate = result.periodStartDate.addMonths(1).addDays(-1);

        result.eligibleAmount = request.eventType == 'OPPORTUNITY_CLOSED_WON' ? request.opportunity.amount : 0;
        result.eligibleAmount = money(result.eligibleAmount);
        result.commissionAmount = money(result.eligibleAmount * result.commissionRate);
        result.finalCommissionAmount = money(result.commissionAmount * result.accelerator);

        return result;
    }

    private static Decimal money(Decimal value) {
        return value == null ? 0 : value.setScale(2, RoundingMode.HALF_UP);
    }
}
