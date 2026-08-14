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
                        // 4-digit hex escape: \u00e9 for \u00E9, \u4e2d for U+4E2D.
                        // The previous code always emitted "\\u00" + 2 low hex
                        // digits, corrupting any char above U+00FF (U+4E2D became
                        // \\u002d, i.e. the character '-').
                        sb.append("\\u");
                        sb.append(hexDigit(c >> 12));
                        sb.append(hexDigit(c >> 8));
                        sb.append(hexDigit(c >> 4));
                        sb.append(hexDigit(c));
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

    private static char hexDigit(int nibble) {
        int n = nibble & 0xF;
        return (char) (n < 10 ? '0' + n : 'a' + n - 10);
    }
}