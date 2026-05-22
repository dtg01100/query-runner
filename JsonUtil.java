public class JsonUtil {

    public static String escapeJson(String str) {
        if (str == null) return "";
        int len = str.length();
        
        // Fast path: no special chars needed (common case for short strings)
        boolean needsEscape = false;
        for (int i = 0; i < len; i++) {
            char c = str.charAt(i);
            if (c == '\\' || c == '"' || c < ' ' || c > 127) {
                needsEscape = true;
                break;
            }
        }
        if (!needsEscape) return str;

        // Slow path: escape needed
        StringBuilder sb = new StringBuilder(len + 16);
        for (int i = 0; i < len; i++) {
            char c = str.charAt(i);
            switch (c) {
                case '\\': sb.append("\\\\"); break;
                case '"': sb.append("\\\""); break;
                case '\b': sb.append("\\b"); break;
                case '\t': sb.append("\\t"); break;
                case '\n': sb.append("\\n"); break;
                case '\f': sb.append("\\f"); break;
                case '\r': sb.append("\\r"); break;
                default:
                    if (c < ' ' || c > 127) {
                        // Use hex string directly instead of String.format
                        sb.append("\\u00");
                        sb.append(Integer.toHexString(c >> 4 & 0xF));
                        sb.append(Integer.toHexString(c & 0xF));
                    } else {
                        sb.append(c);
                    }
                    break;
            }
        }
        return sb.toString();
    }

    public static String escapeJsonEmpty(String str) {
        if (str == null) return "";
        return escapeJson(str);
    }
}