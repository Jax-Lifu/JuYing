package android.util;

public final class Base64 {
    public static final int DEFAULT = 0;
    public static final int NO_PADDING = 1;
    public static final int NO_WRAP = 2;
    public static final int CRLF = 4;
    public static final int URL_SAFE = 8;

    private Base64() {}

    public static byte[] decode(String value, int flags) {
        return decoder(flags).decode(value.replaceAll("\\s", ""));
    }

    public static byte[] decode(byte[] value, int flags) {
        return decode(new String(value, java.nio.charset.StandardCharsets.ISO_8859_1), flags);
    }

    public static byte[] encode(byte[] value, int flags) {
        return encoder(flags).encode(value);
    }

    public static String encodeToString(byte[] value, int flags) {
        return new String(encode(value, flags), java.nio.charset.StandardCharsets.US_ASCII);
    }

    private static java.util.Base64.Decoder decoder(int flags) {
        return (flags & URL_SAFE) != 0
            ? java.util.Base64.getUrlDecoder()
            : java.util.Base64.getDecoder();
    }

    private static java.util.Base64.Encoder encoder(int flags) {
        java.util.Base64.Encoder result = (flags & URL_SAFE) != 0
            ? java.util.Base64.getUrlEncoder()
            : java.util.Base64.getEncoder();
        return (flags & NO_PADDING) != 0 ? result.withoutPadding() : result;
    }
}
