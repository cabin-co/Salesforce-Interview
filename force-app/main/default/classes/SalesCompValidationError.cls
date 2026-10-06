public class SalesCompValidationError {
    public String field;
    public String code;
    public String message;

    public SalesCompValidationError(String field, String code, String message) {
        this.field = field;
        this.code = code;
        this.message = message;
    }
}
