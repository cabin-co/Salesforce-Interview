@RestResource(urlMapping='/api/v1/compensation/calculate')
global with sharing class SalesCompRestResource {
    @HttpPost
    global static void doPost() {
        Savepoint savepoint;
        RestRequest request = RestContext.request;
        SalesCompConfig.Settings settings = SalesCompConfig.get();
        String rawBody = request == null || request.requestBody == null ? null : request.requestBody.toString();
        String idempotencyKey = getHeader(request, 'Idempotency-Key');

        try {
            if (!isAuthorized(request, settings)) {
                writeError(401, 'UNAUTHORIZED', 'Invalid or missing API credentials.', null, null);
                return;
            }

            SalesCompRequest parsedRequest;
            try {
                parsedRequest = (SalesCompRequest) JSON.deserializeStrict(rawBody, SalesCompRequest.class);
            } catch (Exception parseError) {
                writeError(
                    400,
                    'VALIDATION_ERROR',
                    'The request contains invalid JSON.',
                    new List<SalesCompValidationError>{
                        new SalesCompValidationError('body', 'MALFORMED_JSON', parseError.getMessage())
                    },
                    null
                );
                return;
            }

            SalesCompRequestValidator.ValidationResult validation = SalesCompRequestValidator.validate(
                parsedRequest,
                idempotencyKey
            );
            if (!validation.isValid()) {
                writeError(
                    400,
                    'VALIDATION_ERROR',
                    'The request contains invalid fields.',
                    validation.errors,
                    parsedRequest == null ? null : parsedRequest.transactionId
                );
                return;
            }

            List<Sales_Compensation__c> duplicates = [
                SELECT Id, Name, Transaction_Id__c
                FROM Sales_Compensation__c
                WHERE Idempotency_Key__c = :idempotencyKey OR Transaction_Id__c = :parsedRequest.transactionId
                LIMIT 1
            ];
            if (!duplicates.isEmpty()) {
                writeError(
                    409,
                    'DUPLICATE_TRANSACTION',
                    'A compensation transaction already exists for this idempotency key.',
                    null,
                    duplicates[0].Transaction_Id__c
                );
                return;
            }

            savepoint = Database.setSavepoint();
            SalesCompCalculator.CalculationResult calculation = SalesCompCalculator.calculate(parsedRequest);
            Sales_Compensation__c compensation = toCompensationRecord(
                parsedRequest,
                idempotencyKey,
                calculation,
                rawBody
            );
            insert compensation;

            compensation.Webhook_Event_Id__c = SalesCompWebhookService.buildEventId(compensation);
            compensation.Webhook_Payload__c = SalesCompWebhookService.buildPayloadJson(compensation);
            update compensation;

            insertProductLines(compensation.Id, parsedRequest.products);
            System.enqueueJob(new SalesCompWebhookDispatcher(compensation.Id));

            AcceptedResponse response = new AcceptedResponse();
            response.transactionId = parsedRequest.transactionId;
            response.status = 'ACCEPTED';
            response.compensationId = compensation.Name;
            response.webhookStatus = compensation.Webhook_Status__c;
            writeJson(202, response);
        } catch (DmlException dmlError) {
            rollback(savepoint);
            if (isDuplicateDml(dmlError)) {
                writeError(409, 'DUPLICATE_TRANSACTION', 'A compensation transaction already exists.', null, null);
            } else {
                writeError(500, 'INTERNAL_ERROR', 'An unexpected error occurred.', null, null);
            }
        } catch (Exception ex) {
            rollback(savepoint);
            writeError(500, 'INTERNAL_ERROR', 'An unexpected error occurred.', null, null);
        }
    }

    private static Boolean isAuthorized(RestRequest request, SalesCompConfig.Settings settings) {
        if (settings == null || !settings.active || String.isBlank(settings.apiKey)) {
            return false;
        }

        String authHeader = getHeader(request, 'Authorization');
        if (String.isBlank(authHeader) || !authHeader.startsWith('Bearer ')) {
            return false;
        }

        String suppliedToken = authHeader.substring(7).trim();
        return secureEquals(settings.apiKey, suppliedToken);
    }

    private static Sales_Compensation__c toCompensationRecord(
        SalesCompRequest request,
        String idempotencyKey,
        SalesCompCalculator.CalculationResult calculation,
        String rawBody
    ) {
        Sales_Compensation__c compensation = new Sales_Compensation__c();
        compensation.Transaction_Id__c = request.transactionId;
        compensation.Idempotency_Key__c = idempotencyKey;
        compensation.Event_Type__c = request.eventType;
        compensation.Occurred_At__c = request.occurredAt;
        compensation.Status__c = 'CALCULATED';
        compensation.Webhook_Status__c = 'PENDING';
        compensation.Webhook_Attempt_Count__c = 0;
        compensation.Next_Webhook_Attempt_At__c = System.now();

        compensation.Sales_Rep_Id__c = request.salesRep.id;
        compensation.Sales_Rep_External_Id__c = request.salesRep.externalId;
        compensation.Sales_Rep_First_Name__c = request.salesRep.firstName;
        compensation.Sales_Rep_Last_Name__c = request.salesRep.lastName;
        compensation.Sales_Rep_Email__c = request.salesRep.email;
        compensation.Sales_Rep_Role__c = request.salesRep.role;
        compensation.Sales_Rep_Region__c = request.salesRep.region;

        compensation.Source_Opportunity_Id__c = request.opportunity.id;
        compensation.Opportunity_External_Id__c = request.opportunity.externalId;
        compensation.Opportunity_Name__c = truncate(request.opportunity.name, 255);
        compensation.Opportunity_Stage__c = request.opportunity.stage;
        compensation.Opportunity_Close_Date__c = request.opportunity.closeDate;
        compensation.Currency_Code__c = request.opportunity.currency;
        compensation.Opportunity_Amount__c = request.opportunity.amount;
        compensation.Account_Id__c = request.opportunity.account.id;
        compensation.Account_Name__c = truncate(request.opportunity.account.name, 255);

        compensation.Compensation_Plan_Id__c = request.compensationPlan.id;
        compensation.Compensation_Plan_Version__c = request.compensationPlan.version;

        compensation.Eligible_Amount__c = calculation.eligibleAmount;
        compensation.Commission_Rate__c = calculation.commissionRate;
        compensation.Commission_Amount__c = calculation.commissionAmount;
        compensation.Accelerator__c = calculation.accelerator;
        compensation.Final_Commission_Amount__c = calculation.finalCommissionAmount;
        compensation.Period_Type__c = calculation.periodType;
        compensation.Period_Start_Date__c = calculation.periodStartDate;
        compensation.Period_End_Date__c = calculation.periodEndDate;
        compensation.Request_Payload__c = truncate(rawBody, 131072);

        return compensation;
    }

    private static void insertProductLines(Id compensationId, List<SalesCompRequest.ProductLine> products) {
        if (products == null || products.isEmpty()) {
            return;
        }

        List<Sales_Comp_Product__c> productLines = new List<Sales_Comp_Product__c>();
        for (SalesCompRequest.ProductLine product : products) {
            productLines.add(
                new Sales_Comp_Product__c(
                    Compensation__c = compensationId,
                    Product_Id__c = product.productId,
                    Product_Name__c = truncate(product.productName, 255),
                    Quantity__c = product.quantity,
                    Unit_Price__c = product.unitPrice,
                    Amount__c = product.amount
                )
            );
        }
        insert productLines;
    }

    private static void writeError(
        Integer statusCode,
        String code,
        String message,
        List<SalesCompValidationError> details,
        String transactionId
    ) {
        ErrorBody error = new ErrorBody();
        error.code = code;
        error.message = message;
        error.details = details;
        error.transactionId = transactionId;

        ErrorResponse response = new ErrorResponse();
        response.error = error;
        writeJson(statusCode, response);
    }

    private static void writeJson(Integer statusCode, Object body) {
        if (RestContext.response == null) {
            RestContext.response = new RestResponse();
        }
        RestContext.response.statusCode = statusCode;
        RestContext.response.addHeader('Content-Type', 'application/json');
        RestContext.response.responseBody = Blob.valueOf(JSON.serialize(body));
    }

    private static String getHeader(RestRequest request, String headerName) {
        if (request == null || request.headers == null) {
            return null;
        }

        String value = request.headers.get(headerName);
        if (value != null) {
            return value;
        }

        String normalizedHeader = headerName.toLowerCase();
        for (String key : request.headers.keySet()) {
            if (key != null && key.toLowerCase() == normalizedHeader) {
                return request.headers.get(key);
            }
        }
        return null;
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

    private static Boolean isDuplicateDml(DmlException dmlError) {
        for (Integer index = 0; index < dmlError.getNumDml(); index++) {
            if (String.valueOf(dmlError.getDmlStatusCode(index)).contains('DUPLICATE')) {
                return true;
            }
        }
        return false;
    }

    private static void rollback(Savepoint savepoint) {
        if (savepoint != null) {
            Database.rollback(savepoint);
        }
    }

    private static String truncate(String value, Integer maxLength) {
        if (value == null || value.length() <= maxLength) {
            return value;
        }
        return value.substring(0, maxLength);
    }

    private class AcceptedResponse {
        public String transactionId;
        public String status;
        public String compensationId;
        public String webhookStatus;
    }

    private class ErrorResponse {
        public ErrorBody error;
    }

    private class ErrorBody {
        public String code;
        public String message;
        public List<SalesCompValidationError> details;
        public String transactionId;
    }
}
