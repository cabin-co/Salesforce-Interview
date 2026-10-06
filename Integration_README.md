# Sales Compensation Integration

## Technical Requirements Specification

**Version:** 1.0
**Status:** Draft
**Audience:** Integration developers, API developers, QA engineers
**System:** Acme Sales Compensation Platform

---

# 1. Overview

The Acme Sales Compensation Platform calculates sales compensation for sales representatives based on opportunity and transaction data received from an external CRM or sales system.

The integration has two primary responsibilities:

1. Accept sales transaction data from an external system through an API.
2. Calculate the applicable sales compensation and notify the external system of the result through a webhook.

The external system is responsible for maintaining the source-of-truth records for users and opportunities.

The Acme Sales Compensation Platform is responsible for determining the compensation earned from an eligible transaction.

## High-Level Flow

```text
External CRM
     |
     |  POST /api/v1/compensation/calculate
     |  User + Opportunity + Transaction
     v
Sales Compensation Platform
     |
     |  Calculate compensation
     |
     |  POST Webhook
     v
External CRM
     |
     |  Sales Compensation Result
     v
External CRM
```

---

# 2. Integration Assumptions

The external system will provide the following information:

* Sales representative information
* Opportunity information
* Opportunity amount
* Currency
* Opportunity stage
* Close date
* Product or transaction information
* Compensation plan identifier

The compensation platform will use this information to determine the applicable compensation.

The external system should not calculate the commission itself.

---

# 3. Authentication

All API requests must authenticate using an API key.

The API key must be supplied using the following HTTP header:

```http
Authorization: Bearer {API_KEY}
```

Requests without valid authentication must receive:

```http
HTTP/1.1 401 Unauthorized
```

---

# 4. Calculate Compensation API

## Endpoint

```http
POST /api/v1/compensation/calculate
```

## Request Headers

```http
Content-Type: application/json
Authorization: Bearer {API_KEY}
Idempotency-Key: {UNIQUE_TRANSACTION_ID}
```

The `Idempotency-Key` must uniquely identify the compensation transaction.

If the same transaction is submitted more than once using the same idempotency key, the platform must not create duplicate compensation records.

---

# 5. Compensation Calculation Request

## Example Request

```json
{
  "transactionId": "TXN-2026-000184",
  "eventType": "OPPORTUNITY_CLOSED_WON",
  "occurredAt": "2026-10-06T17:30:00Z",

  "salesRep": {
    "id": "0058A000001ABCQ",
    "externalId": "REP-10482",
    "firstName": "Jane",
    "lastName": "Smith",
    "email": "jane.smith@example.com",
    "role": "ACCOUNT_EXECUTIVE",
    "region": "WEST"
  },

  "opportunity": {
    "id": "0068A000002XYZQ",
    "externalId": "OPP-2026-9182",
    "name": "Acme Corporation - Enterprise Agreement",
    "stage": "CLOSED_WON",
    "closeDate": "2026-10-06",
    "currency": "USD",
    "amount": 125000.00,
    "account": {
      "id": "0018A000004LMNQ",
      "name": "Acme Corporation"
    }
  },

  "compensationPlan": {
    "id": "PLAN-AE-2026",
    "version": 3
  },

  "products": [
    {
      "productId": "PROD-ENT-001",
      "productName": "Enterprise Platform",
      "quantity": 1,
      "unitPrice": 100000.00,
      "amount": 100000.00
    },
    {
      "productId": "PROD-SVC-001",
      "productName": "Professional Services",
      "quantity": 1,
      "unitPrice": 25000.00,
      "amount": 25000.00
    }
  ]
}
```

---

# 6. Request Field Definitions

| Field              | Type     | Required | Description                                          |
| ------------------ | -------- | -------: | ---------------------------------------------------- |
| `transactionId`    | string   |      Yes | Unique identifier for the compensation transaction   |
| `eventType`        | string   |      Yes | Event that triggered compensation calculation        |
| `occurredAt`       | datetime |      Yes | Timestamp when the event occurred                    |
| `salesRep`         | object   |      Yes | Sales representative associated with the transaction |
| `opportunity`      | object   |      Yes | Opportunity associated with the transaction          |
| `compensationPlan` | object   |      Yes | Compensation plan used for calculation               |
| `products`         | array    |       No | Products or services included in the transaction     |

## Event Types

The following event types are currently supported:

* `OPPORTUNITY_CLOSED_WON`
* `OPPORTUNITY_CLOSED_LOST`
* `OPPORTUNITY_UPDATED`
* `OPPORTUNITY_CANCELLED`

Only `OPPORTUNITY_CLOSED_WON` currently generates positive compensation.

---

# 7. Sales Representative

| Field        | Type   | Required | Description                                    |
| ------------ | ------ | -------: | ---------------------------------------------- |
| `id`         | string |      Yes | Unique identifier for the sales representative |
| `externalId` | string |      Yes | Identifier used by the external CRM            |
| `firstName`  | string |      Yes | First name                                     |
| `lastName`   | string |      Yes | Last name                                      |
| `email`      | string |      Yes | Business email                                 |
| `role`       | string |      Yes | Sales role                                     |
| `region`     | string |      Yes | Compensation region                            |

## Supported Roles

```text
ACCOUNT_EXECUTIVE
SALES_DEVELOPMENT_REP
ACCOUNT_MANAGER
SALES_MANAGER
```

---

# 8. Opportunity

| Field        | Type    | Required | Description                     |
| ------------ | ------- | -------: | ------------------------------- |
| `id`         | string  |      Yes | Internal CRM opportunity ID     |
| `externalId` | string  |      Yes | External opportunity identifier |
| `name`       | string  |      Yes | Opportunity name                |
| `stage`      | string  |      Yes | Current opportunity stage       |
| `closeDate`  | date    |      Yes | Opportunity close date          |
| `currency`   | string  |      Yes | ISO 4217 currency code          |
| `amount`     | decimal |      Yes | Total opportunity value         |
| `account`    | object  |      Yes | Customer account                |

## Supported Opportunity Stages

```text
PROSPECTING
QUALIFICATION
PROPOSAL
NEGOTIATION
CLOSED_WON
CLOSED_LOST
```

---

# 9. Compensation Plan

The compensation plan determines which compensation rules are applied.

```json
{
  "id": "PLAN-AE-2026",
  "version": 3
}
```

The combination of `id` and `version` uniquely identifies a compensation plan.

The external system must provide the plan identifier but does not need to know the individual calculation rules.

---

# 10. Compensation Calculation Rules

For purposes of this integration, compensation is calculated using the following simplified rules.

## Base Commission

Account Executives receive:

```text
10% of eligible opportunity amount
```

Sales Development Representatives receive:

```text
5% of eligible opportunity amount
```

Account Managers receive:

```text
7% of eligible opportunity amount
```

Sales Managers receive:

```text
3% of eligible opportunity amount
```

## Example

For an Account Executive closing a $125,000 opportunity:

```text
Eligible Amount = $125,000
Commission Rate = 10%

Commission = $125,000 × 10%
           = $12,500
```

---

# 11. Compensation Response

The calculation API returns an acknowledgement that the transaction has been accepted.

```json
{
  "transactionId": "TXN-2026-000184",
  "status": "ACCEPTED",
  "compensationId": "COMP-2026-009821",
  "webhookStatus": "PENDING"
}
```

The final compensation result is delivered asynchronously through the webhook.

---

# 12. Compensation Webhook

Once compensation has been calculated, the platform sends a webhook to the external system.

## HTTP Method

```http
POST
```

## Example Endpoint

The webhook URL is configured when the integration is established.

For example:

```http
https://crm.example.com/api/webhooks/sales-compensation
```

---

# 13. Webhook Request

The webhook contains the complete compensation result.

## Example

```json
{
  "eventId": "EVT-2026-009821",
  "eventType": "COMPENSATION_CALCULATED",
  "eventVersion": "1.0",
  "occurredAt": "2026-10-06T17:31:04Z",

  "compensation": {
    "id": "COMP-2026-009821",
    "status": "CALCULATED",

    "transaction": {
      "id": "TXN-2026-000184",
      "type": "OPPORTUNITY_CLOSED_WON"
    },

    "salesRep": {
      "id": "0058A000001ABCQ",
      "externalId": "REP-10482"
    },

    "opportunity": {
      "id": "0068A000002XYZQ",
      "externalId": "OPP-2026-9182"
    },

    "compensationPlan": {
      "id": "PLAN-AE-2026",
      "version": 3
    },

    "calculation": {
      "currency": "USD",
      "eligibleAmount": 125000.00,
      "commissionRate": 0.10,
      "commissionAmount": 12500.00,
      "accelerator": 1.0,
      "finalCommissionAmount": 12500.00
    },

    "period": {
      "type": "MONTH",
      "startDate": "2026-10-01",
      "endDate": "2026-10-31"
    }
  }
}
```

---

# 14. Webhook Field Definitions

| Field          | Type     | Required | Description                             |
| -------------- | -------- | -------: | --------------------------------------- |
| `eventId`      | string   |      Yes | Unique identifier for the webhook event |
| `eventType`    | string   |      Yes | Type of event                           |
| `eventVersion` | string   |      Yes | Version of the webhook contract         |
| `occurredAt`   | datetime |      Yes | Time the event was generated            |
| `compensation` | object   |      Yes | Compensation result                     |

## Compensation

| Field              | Type   | Required | Description                   |
| ------------------ | ------ | -------: | ----------------------------- |
| `id`               | string |      Yes | Unique compensation record ID |
| `status`           | string |      Yes | Current compensation status   |
| `transaction`      | object |      Yes | Source transaction            |
| `salesRep`         | object |      Yes | Sales representative          |
| `opportunity`      | object |      Yes | Source opportunity            |
| `compensationPlan` | object |      Yes | Plan used                     |
| `calculation`      | object |      Yes | Calculation details           |
| `period`           | object |      Yes | Compensation period           |

---

# 15. Calculation Object

The calculation object must expose enough information for the receiving system to understand how the compensation amount was determined.

| Field                   | Type    | Description                            |
| ----------------------- | ------- | -------------------------------------- |
| `currency`              | string  | ISO 4217 currency code                 |
| `eligibleAmount`        | decimal | Amount eligible for commission         |
| `commissionRate`        | decimal | Commission rate expressed as a decimal |
| `commissionAmount`      | decimal | Base calculated commission             |
| `accelerator`           | decimal | Multiplier applied to the commission   |
| `finalCommissionAmount` | decimal | Final compensation amount              |

For example:

```json
{
  "eligibleAmount": 125000.00,
  "commissionRate": 0.10,
  "commissionAmount": 12500.00,
  "accelerator": 1.25,
  "finalCommissionAmount": 15625.00
}
```

The calculation should satisfy:

```text
commissionAmount =
    eligibleAmount × commissionRate

finalCommissionAmount =
    commissionAmount × accelerator
```

---

# 16. Compensation Statuses

A compensation record may have one of the following statuses:

```text
CALCULATING
CALCULATED
APPROVED
PAID
CANCELLED
REVERSED
```

The initial webhook generated by this integration will normally contain:

```text
CALCULATED
```

---

# 17. Compensation Period

The compensation period identifies the accounting period to which the commission belongs.

```json
{
  "type": "MONTH",
  "startDate": "2026-10-01",
  "endDate": "2026-10-31"
}
```

Supported period types:

```text
MONTH
QUARTER
YEAR
```

---

# 18. JSON Schema — Calculation Request

The following JSON Schema defines the request contract.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://api.example.com/schemas/compensation-request.json",
  "title": "Compensation Calculation Request",
  "type": "object",
  "additionalProperties": false,
  "required": [
    "transactionId",
    "eventType",
    "occurredAt",
    "salesRep",
    "opportunity",
    "compensationPlan"
  ],
  "properties": {
    "transactionId": {
      "type": "string",
      "minLength": 1
    },
    "eventType": {
      "type": "string",
      "enum": [
        "OPPORTUNITY_CLOSED_WON",
        "OPPORTUNITY_CLOSED_LOST",
        "OPPORTUNITY_UPDATED",
        "OPPORTUNITY_CANCELLED"
      ]
    },
    "occurredAt": {
      "type": "string",
      "format": "date-time"
    },
    "salesRep": {
      "$ref": "#/$defs/salesRep"
    },
    "opportunity": {
      "$ref": "#/$defs/opportunity"
    },
    "compensationPlan": {
      "$ref": "#/$defs/compensationPlan"
    },
    "products": {
      "type": "array",
      "items": {
        "$ref": "#/$defs/product"
      }
    }
  },

  "$defs": {
    "salesRep": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "externalId",
        "firstName",
        "lastName",
        "email",
        "role",
        "region"
      ],
      "properties": {
        "id": {
          "type": "string"
        },
        "externalId": {
          "type": "string"
        },
        "firstName": {
          "type": "string"
        },
        "lastName": {
          "type": "string"
        },
        "email": {
          "type": "string",
          "format": "email"
        },
        "role": {
          "type": "string",
          "enum": [
            "ACCOUNT_EXECUTIVE",
            "SALES_DEVELOPMENT_REP",
            "ACCOUNT_MANAGER",
            "SALES_MANAGER"
          ]
        },
        "region": {
          "type": "string"
        }
      }
    },

    "opportunity": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "externalId",
        "name",
        "stage",
        "closeDate",
        "currency",
        "amount",
        "account"
      ],
      "properties": {
        "id": {
          "type": "string"
        },
        "externalId": {
          "type": "string"
        },
        "name": {
          "type": "string"
        },
        "stage": {
          "type": "string",
          "enum": [
            "PROSPECTING",
            "QUALIFICATION",
            "PROPOSAL",
            "NEGOTIATION",
            "CLOSED_WON",
            "CLOSED_LOST"
          ]
        },
        "closeDate": {
          "type": "string",
          "format": "date"
        },
        "currency": {
          "type": "string",
          "pattern": "^[A-Z]{3}$"
        },
        "amount": {
          "type": "number",
          "minimum": 0
        },
        "account": {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "id",
            "name"
          ],
          "properties": {
            "id": {
              "type": "string"
            },
            "name": {
              "type": "string"
            }
          }
        }
      }
    },

    "compensationPlan": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "id",
        "version"
      ],
      "properties": {
        "id": {
          "type": "string"
        },
        "version": {
          "type": "integer",
          "minimum": 1
        }
      }
    },

    "product": {
      "type": "object",
      "additionalProperties": false,
      "required": [
        "productId",
        "productName",
        "quantity",
        "unitPrice",
        "amount"
      ],
      "properties": {
        "productId": {
          "type": "string"
        },
        "productName": {
          "type": "string"
        },
        "quantity": {
          "type": "number",
          "exclusiveMinimum": 0
        },
        "unitPrice": {
          "type": "number",
          "minimum": 0
        },
        "amount": {
          "type": "number",
          "minimum": 0
        }
      }
    }
  }
}
```

---

# 19. JSON Schema — Compensation Webhook

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://api.example.com/schemas/compensation-webhook.json",
  "title": "Compensation Calculated Webhook",
  "type": "object",
  "additionalProperties": false,

  "required": [
    "eventId",
    "eventType",
    "eventVersion",
    "occurredAt",
    "compensation"
  ],

  "properties": {
    "eventId": {
      "type": "string"
    },

    "eventType": {
      "type": "string",
      "const": "COMPENSATION_CALCULATED"
    },

    "eventVersion": {
      "type": "string"
    },

    "occurredAt": {
      "type": "string",
      "format": "date-time"
    },

    "compensation": {
      "type": "object",
      "additionalProperties": false,

      "required": [
        "id",
        "status",
        "transaction",
        "salesRep",
        "opportunity",
        "compensationPlan",
        "calculation",
        "period"
      ],

      "properties": {
        "id": {
          "type": "string"
        },

        "status": {
          "type": "string",
          "enum": [
            "CALCULATING",
            "CALCULATED",
            "APPROVED",
            "PAID",
            "CANCELLED",
            "REVERSED"
          ]
        },

        "transaction": {
          "type": "object",
          "required": [
            "id",
            "type"
          ],
          "properties": {
            "id": {
              "type": "string"
            },
            "type": {
              "type": "string"
            }
          }
        },

        "salesRep": {
          "type": "object",
          "required": [
            "id",
            "externalId"
          ],
          "properties": {
            "id": {
              "type": "string"
            },
            "externalId": {
              "type": "string"
            }
          }
        },

        "opportunity": {
          "type": "object",
          "required": [
            "id",
            "externalId"
          ],
          "properties": {
            "id": {
              "type": "string"
            },
            "externalId": {
              "type": "string"
            }
          }
        },

        "compensationPlan": {
          "type": "object",
          "required": [
            "id",
            "version"
          ],
          "properties": {
            "id": {
              "type": "string"
            },
            "version": {
              "type": "integer"
            }
          }
        },

        "calculation": {
          "type": "object",
          "required": [
            "currency",
            "eligibleAmount",
            "commissionRate",
            "commissionAmount",
            "accelerator",
            "finalCommissionAmount"
          ],
          "properties": {
            "currency": {
              "type": "string",
              "pattern": "^[A-Z]{3}$"
            },
            "eligibleAmount": {
              "type": "number"
            },
            "commissionRate": {
              "type": "number",
              "minimum": 0
            },
            "commissionAmount": {
              "type": "number",
              "minimum": 0
            },
            "accelerator": {
              "type": "number",
              "minimum": 0
            },
            "finalCommissionAmount": {
              "type": "number",
              "minimum": 0
            }
          }
        },

        "period": {
          "type": "object",
          "required": [
            "type",
            "startDate",
            "endDate"
          ],
          "properties": {
            "type": {
              "type": "string",
              "enum": [
                "MONTH",
                "QUARTER",
                "YEAR"
              ]
            },
            "startDate": {
              "type": "string",
              "format": "date"
            },
            "endDate": {
              "type": "string",
              "format": "date"
            }
          }
        }
      }
    }
  }
}
```

---

# 20. Webhook Security

Webhook requests must include an HMAC signature.

The signature is calculated using the raw request body and a shared secret.

Example:

```http
X-Compensation-Signature: sha256=9c4e...
```

The receiving system must validate the signature before processing the webhook.

The receiver should reject requests with an invalid signature:

```http
HTTP/1.1 401 Unauthorized
```

---

# 21. Webhook Response

The receiving system must acknowledge successful processing with:

```http
HTTP/1.1 200 OK
```

Example response:

```json
{
  "received": true,
  "eventId": "EVT-2026-009821"
}
```

---

# 22. Retry Behavior

If the webhook recipient does not return a successful HTTP response, the compensation platform will retry delivery.

Retries will occur at approximately:

```text
Attempt 1: Immediate
Attempt 2: 30 seconds
Attempt 3: 2 minutes
Attempt 4: 10 minutes
Attempt 5: 30 minutes
Attempt 6: 2 hours
```

The external system must therefore process webhook events idempotently.

An event with an `eventId` that has already been successfully processed should return `200 OK` without creating a duplicate compensation record.

---

# 23. API Errors

## Validation Error

```http
HTTP/1.1 400 Bad Request
```

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "The request contains invalid fields.",
    "details": [
      {
        "field": "opportunity.amount",
        "code": "MUST_BE_GREATER_THAN_ZERO",
        "message": "Opportunity amount must be greater than zero."
      }
    ]
  }
}
```

## Unauthorized

```http
HTTP/1.1 401 Unauthorized
```

```json
{
  "error": {
    "code": "UNAUTHORIZED",
    "message": "Invalid or missing API credentials."
  }
}
```

## Duplicate Transaction

```http
HTTP/1.1 409 Conflict
```

```json
{
  "error": {
    "code": "DUPLICATE_TRANSACTION",
    "message": "A compensation transaction already exists for this idempotency key.",
    "transactionId": "TXN-2026-000184"
  }
}
```

## Internal Error

```http
HTTP/1.1 500 Internal Server Error
```

```json
{
  "error": {
    "code": "INTERNAL_ERROR",
    "message": "An unexpected error occurred."
  }
}
```

---

# 24. Business Requirements

The implementation must satisfy the following requirements.

### BR-001 — Transaction Identification

Every compensation transaction must have a unique transaction identifier.

### BR-002 — Sales Representative

Every compensation transaction must identify the sales representative responsible for the opportunity.

### BR-003 — Opportunity

Every compensation transaction must reference the originating opportunity.

### BR-004 — Compensation Plan

Every transaction must specify the compensation plan and plan version used for calculation.

### BR-005 — Calculation Transparency

The webhook must expose the inputs and intermediate values required to understand the final compensation amount.

At minimum this includes:

* Eligible amount
* Commission rate
* Commission amount
* Accelerator
* Final commission amount

### BR-006 — Idempotency

Repeated delivery of the same transaction or webhook event must not create duplicate compensation records.

### BR-007 — Auditability

A compensation result must be traceable back to:

```text
Compensation
    ↓
Transaction
    ↓
Opportunity
    ↓
Sales Representative
    ↓
Compensation Plan
```

### BR-008 — Currency

Monetary amounts must always include a currency.

### BR-009 — Asynchronous Processing

The initial calculation API must not require the external system to wait for the final compensation calculation.

The API acknowledges receipt, and the final result is delivered asynchronously through the webhook.

---

# 25. Example End-to-End Scenario

Jane Smith is an Account Executive.

She closes an opportunity worth $125,000.

Her compensation plan specifies a 10% commission rate.

The external system sends:

```text
Transaction: TXN-2026-000184
Opportunity: OPP-2026-9182
Sales Rep: REP-10482
Amount: $125,000
Plan: PLAN-AE-2026 v3
```

The compensation platform calculates:

```text
Eligible Amount       $125,000
Commission Rate            10%
Base Commission         $12,500
Accelerator                  1.0
Final Commission        $12,500
```

The external system initially receives:

```json
{
  "transactionId": "TXN-2026-000184",
  "status": "ACCEPTED",
  "compensationId": "COMP-2026-009821",
  "webhookStatus": "PENDING"
}
```

The external system subsequently receives the webhook containing:

```json
{
  "eventType": "COMPENSATION_CALCULATED",
  "compensation": {
    "id": "COMP-2026-009821",
    "status": "CALCULATED",
    "calculation": {
      "currency": "USD",
      "eligibleAmount": 125000.00,
      "commissionRate": 0.10,
      "commissionAmount": 12500.00,
      "accelerator": 1.0,
      "finalCommissionAmount": 12500.00
    }
  }
}
```

The external system should use `compensation.id` as the unique identifier for the resulting compensation record and retain the source `transactionId` and `opportunity.externalId` for reconciliation.

---

# 26. Candidate Implementation Requirements

The candidate should implement an integration that:

1. Accepts the compensation calculation request.
2. Validates the request against the documented contract.
3. Identifies the applicable compensation plan.
4. Calculates the commission.
5. Creates a compensation result.
6. Returns an appropriate API response.
7. Publishes the compensation result through a webhook.
8. Validates webhook signatures.
9. Handles webhook retries safely.
10. Prevents duplicate processing of transactions.
11. Handles invalid input appropriately.
12. Provides sufficient logging to troubleshoot a failed transaction.

The implementation should demonstrate appropriate separation between:

* API/request handling
* Validation
* Business logic
* Compensation calculation
* Persistence
* Webhook delivery
* Error handling

---

# 27. Out of Scope

The following are intentionally outside the scope of this exercise:

* User authentication/SSO
* Building a complete CRM
* Payroll processing
* Tax calculation
* Payment processing
* Compensation plan administration UI
* Full production-grade infrastructure
* Multi-currency conversion
* Real-time exchange rates

---

# 28. Evaluation Considerations

The implementation will be evaluated on:

* Correctness of the API contract
* JSON validation
* Data modeling
* Compensation calculation
* Error handling
* Idempotency
* Webhook implementation
* Security considerations
* Code organization
* Test coverage
* Ability to handle edge cases
* Clarity of implementation

The candidate should be able to explain the design decisions made during implementation and identify areas that would need additional consideration for a production deployment.
