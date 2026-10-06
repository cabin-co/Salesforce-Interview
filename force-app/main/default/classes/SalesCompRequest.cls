public class SalesCompRequest {
    public String transactionId;
    public String eventType;
    public Datetime occurredAt;
    public SalesRep salesRep;
    public OpportunityInfo opportunity;
    public CompensationPlan compensationPlan;
    public List<ProductLine> products;

    public class SalesRep {
        public String id;
        public String externalId;
        public String firstName;
        public String lastName;
        public String email;
        public String role;
        public String region;
    }

    public class OpportunityInfo {
        public String id;
        public String externalId;
        public String name;
        public String stage;
        public Date closeDate;
        public String currency;
        public Decimal amount;
        public AccountInfo account;
    }

    public class AccountInfo {
        public String id;
        public String name;
    }

    public class CompensationPlan {
        public String id;
        public Integer version;
    }

    public class ProductLine {
        public String productId;
        public String productName;
        public Decimal quantity;
        public Decimal unitPrice;
        public Decimal amount;
    }
}
