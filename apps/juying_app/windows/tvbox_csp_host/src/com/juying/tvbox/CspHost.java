package com.juying.tvbox;

import com.github.catvod.crawler.Spider;
import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.HashMap;
import java.util.List;
import java.util.Iterator;
import org.json.JSONArray;
import org.json.JSONObject;
import android.app.Application;

public final class CspHost {
    public static void main(String[] args) {
        PrintStream protocol = System.out;
        System.setOut(new PrintStream(System.err, true, StandardCharsets.UTF_8));
        try {
            if (args.length != 1) throw new IllegalArgumentException("缺少 CSP 类名");
            JSONObject request = new JSONObject(readStdin());
            Spider spider = (Spider) Class.forName(args[0]).getDeclaredConstructor().newInstance();
            spider.init(new Application(), request.optString("ext", ""));
            JSONArray rawArgs = request.optJSONArray("args");
            List<Object> values = new ArrayList<>();
            if (rawArgs != null) {
                for (int i = 0; i < rawArgs.length(); i++) values.add(rawArgs.opt(i));
            }
            String result = invoke(spider, request.getString("method"), values);
            write(protocol, true, result == null ? "" : result);
        } catch (Throwable error) {
            Throwable cause = error.getCause() == null ? error : error.getCause();
            write(protocol, false, cause.getClass().getSimpleName() + ": " + cause.getMessage());
        }
    }

    private static String invoke(Spider spider, String method, List<Object> args) throws Exception {
        return switch (method) {
            case "home" -> spider.homeContent(booleanAt(args, 0));
            case "category" -> spider.categoryContent(
                stringAt(args, 0), stringAt(args, 1), booleanAt(args, 2), mapAt(args, 3));
            case "detail" -> spider.detailContent(List.of(stringAt(args, 0)));
            case "search" -> spider.searchContent(
                stringAt(args, 0), booleanAt(args, 1), stringAt(args, 2));
            case "play" -> spider.playerContent(
                stringAt(args, 0), stringAt(args, 1), stringsAt(args, 2));
            default -> throw new IllegalArgumentException("不支持的 CSP 方法: " + method);
        };
    }

    private static String readStdin() throws Exception {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        System.in.transferTo(bytes);
        return bytes.toString(StandardCharsets.UTF_8);
    }

    private static String stringAt(List<Object> args, int index) {
        if (index >= args.size() || args.get(index) == null) return "";
        return String.valueOf(args.get(index));
    }

    private static boolean booleanAt(List<Object> args, int index) {
        return index < args.size() && Boolean.parseBoolean(String.valueOf(args.get(index)));
    }

    private static HashMap<String, String> mapAt(List<Object> args, int index) {
        HashMap<String, String> result = new HashMap<>();
        if (index >= args.size() || !(args.get(index) instanceof JSONObject value)) return result;
        Iterator<?> keys = value.keys();
        while (keys.hasNext()) {
            String key = String.valueOf(keys.next());
            result.put(key, String.valueOf(value.opt(key)));
        }
        return result;
    }

    private static List<String> stringsAt(List<Object> args, int index) {
        List<String> result = new ArrayList<>();
        if (index >= args.size() || !(args.get(index) instanceof JSONArray value)) return result;
        for (int i = 0; i < value.length(); i++) result.add(String.valueOf(value.opt(i)));
        return result;
    }

    private static void write(PrintStream output, boolean ok, String value) {
        String encoded = Base64.getEncoder().encodeToString(value.getBytes(StandardCharsets.UTF_8));
        output.print(ok
            ? "{\"ok\":true,\"resultBase64\":\"" + encoded + "\"}"
            : "{\"ok\":false,\"errorBase64\":\"" + encoded + "\"}");
        output.flush();
    }
}
