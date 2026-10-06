public with sharing class SalesCompRequestValidator {
    private static final Set<String> EVENT_TYPES = new Set<String>{
        'OPPORTUNITY_CLOSED_WON',
        'OPPORTUNITY_CLOSED_LOST',
        'OPPORTUNITY_UPDATED',
        'OPPORTUNITY_CANCELLED'
    };
    private static final Set<String> SALES_ROLES = new Set<String>{
        'ACCOUNT_EXECUTIVE',
        'SALES_DEVELOPMENT_REP',
        'ACCOUNT_MANAGER',
        'SALES_MANAGER'
    };
    private static final Set<String> OPPORTUNITY_STAGES = new Set<String>{
        'PROSPECTING',
        'QUALIFICATION',
        'PROPOSAL',
        'NEGOTIATION',
        'CLOSED_WON',
        'CLOSED_LOST'
    };

    public class ValidationResult {
        public List<SalesCompValidationError> errors = new List<SalesCompValidationError>();

        public Boolean isValid() {
            return errors.isEmpty();
        }
    }

    public static ValidationResult validate(SalesCompRequest request, String idempotencyKey) {
        ValidationResult result = new ValidationResult();

        if (String.isBlank(idempotencyKey)) {
            add(result, 'headers.Idempotency-Key', 'REQUIRED', 'Idempotency-Key header is required.');
        }

        if (request == null) {
            add(result, 'body', 'REQUIRED', 'Request body is required.');
            return result;
        }

        requiredString(result, 'transactionId', request.transactionId);
        requiredString(result, 'eventType', request.eventType);
        if (!String.isBlank(request.eventType) && !EVENT_TYPES.contains(request.eventType)) {
            add(result, 'eventType', 'UNSUPPORTED_VALUE', 'Unsupported compensation event type.');
        }
        if (request.occurredAt == null) {
            add(result, 'occurredAt', 'REQUIRED', 'occurredAt is required.');
        }

        validateSalesRep(result, request.salesRep);
        validateOpportunity(result, request.opportunity, request.eventType);
        validateCompensationPlan(result, request.compensationPlan);
        validateProducts(result, request.products);

        return result;
    }

    private static void validateSalesRep(ValidationResult result, SalesCompRequest.SalesRep salesRep) {
        if (salesRep == null) {
            add(result, 'salesRep', 'REQUIRED', 'salesRep is required.');
            return;
        }

        requiredString(result, 'salesRep.id', salesRep.id);
        requiredString(result, 'salesRep.externalId', salesRep.externalId);
        requiredString(result, 'salesRep.firstName', salesRep.firstName);
        requiredString(result, 'salesRep.lastName', salesRep.lastName);
        requiredString(result, 'salesRep.email', salesRep.email);
        if (!String.isBlank(salesRep.email) && !isEmailLike(salesRep.email)) {
            add(result, 'salesRep.email', 'INVALID_EMAIL', 'salesRep.email must be a valid email address.');
        }
        requiredString(result, 'salesRep.role', salesRep.role);
        if (!String.isBlank(salesRep.role) && !SALES_ROLES.contains(salesRep.role)) {
            add(result, 'salesRep.role', 'UNSUPPORTED_VALUE', 'Unsupported sales representative role.');
        }
        requiredString(result, 'salesRep.region', salesRep.region);
    }

    private static void validateOpportunity(
        ValidationResult result,
        SalesCompRequest.OpportunityInfo opportunity,
        String requestEventType
    ) {
        if (opportunity == null) {
            add(result, 'opportunity', 'REQUIRED', 'opportunity is required.');
            return;
        }

        requiredString(result, 'opportunity.id', opportunity.id);
        requiredString(result, 'opportunity.externalId', opportunity.externalId);
        requiredString(result, 'opportunity.name', opportunity.name);
        requiredString(result, 'opportunity.stage', opportunity.stage);
        if (!String.isBlank(opportunity.stage) && !OPPORTUNITY_STAGES.contains(opportunity.stage)) {
            add(result, 'opportunity.stage', 'UNSUPPORTED_VALUE', 'Unsupported opportunity stage.');
        }
        if (opportunity.closeDate == null) {
            add(result, 'opportunity.closeDate', 'REQUIRED', 'opportunity.closeDate is required.');
        }
        requiredString(result, 'opportunity.currency', opportunity.currency);
        if (!String.isBlank(opportunity.currency) && !isIsoCurrency(opportunity.currency)) {
            add(result, 'opportunity.currency', 'INVALID_CURRENCY', 'opportunity.currency must be a three-letter ISO 4217 code.');
        }
        if (opportunity.amount == null) {
            add(result, 'opportunity.amount', 'REQUIRED', 'opportunity.amount is required.');
        } else if (opportunity.amount < 0) {
            add(result, 'opportunity.amount', 'MUST_NOT_BE_NEGATIVE', 'Opportunity amount must not be negative.');
        } else if (requestEventType == 'OPPORTUNITY_CLOSED_WON' && opportunity.amount == 0) {
            add(result, 'opportunity.amount', 'MUST_BE_GREATER_THAN_ZERO', 'Closed won opportunity amount must be greater than zero.');
        }

        if (opportunity.account == null) {
            add(result, 'opportunity.account', 'REQUIRED', 'opportunity.account is required.');
        } else {
            requiredString(result, 'opportunity.account.id', opportunity.account.id);
            requiredString(result, 'opportunity.account.name', opportunity.account.name);
        }
    }

    private static void validateCompensationPlan(ValidationResult result, SalesCompRequest.CompensationPlan plan) {
        if (plan == null) {
            add(result, 'compensationPlan', 'REQUIRED', 'compensationPlan is required.');
            return;
        }

        requiredString(result, 'compensationPlan.id', plan.id);
        if (plan.version == null) {
            add(result, 'compensationPlan.version', 'REQUIRED', 'compensationPlan.version is required.');
        } else if (plan.version < 1) {
            add(result, 'compensationPlan.version', 'MUST_BE_GREATER_THAN_ZERO', 'compensationPlan.version must be greater than zero.');
        }
    }

    private static void validateProducts(ValidationResult result, List<SalesCompRequest.ProductLine> products) {
        if (products == null) {
            return;
        }

        for (Integer index = 0; index < products.size(); index++) {
            SalesCompRequest.ProductLine product = products[index];
            String prefix = 'products[' + index + ']';
            if (product == null) {
                add(result, prefix, 'REQUIRED', 'Product line must not be null.');
                continue;
            }

            requiredString(result, prefix + '.productId', product.productId);
            requiredString(result, prefix + '.productName', product.productName);
            if (product.quantity == null || product.quantity <= 0) {
                add(result, prefix + '.quantity', 'MUST_BE_GREATER_THAN_ZERO', 'Product quantity must be greater than zero.');
            }
            if (product.unitPrice == null || product.unitPrice < 0) {
                add(result, prefix + '.unitPrice', 'MUST_NOT_BE_NEGATIVE', 'Product unitPrice must not be negative.');
            }
            if (product.amount == null || product.amount < 0) {
                add(result, prefix + '.amount', 'MUST_NOT_BE_NEGATIVE', 'Product amount must not be negative.');
            }
        }
    }

    private static void requiredString(ValidationResult result, String field, String value) {
        if (String.isBlank(value)) {
            add(result, field, 'REQUIRED', field + ' is required.');
        }
    }

    private static void add(ValidationResult result, String field, String code, String message) {
        result.errors.add(new SalesCompValidationError(field, code, message));
    }

    private static Boolean isIsoCurrency(String value) {
        return value != null &&
            value.length() == 3 &&
            value == value.toUpperCase() &&
            value.replaceAll('[A-Z]', '') == '';
    }

    private static Boolean isEmailLike(String value) {
        return value != null && value.contains('@') && value.contains('.');
    }
}
