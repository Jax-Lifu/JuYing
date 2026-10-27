package com.github.catvod.spider;

import android.content.Context;
import com.github.catvod.crawler.Spider;
import org.json.JSONArray;
import org.json.JSONObject;
import java.util.HashMap;
import java.util.List;

/** Original test spider: the test APK is also a DEX-containing JAR fixture. */
public class Fixture extends Spider {
    private String base;

    @Override public void init(Context context, String extend) {
        if (Init.calls != 1 || safeDns() == null) throw new IllegalStateException("Missing CatVod initialization");
        com.github.catvod.crawler.SpiderDebug.log("fixture");
        base = extend;
    }

    @Override public String homeContent(boolean filter) {
        return "{\"class\":[{\"type_id\":\"films\",\"type_name\":\"测试分类\"}]}";
    }

    private String video(String title) throws Exception {
        JSONObject item = new JSONObject().put("vod_id", "movie").put("vod_name", title)
            .put("vod_play_from", "原生").put("vod_play_url", "第一集$episode");
        return new JSONObject().put("list", new JSONArray().put(item)).toString();
    }

    @Override public String categoryContent(String tid, String pg, boolean filter, HashMap<String, String> extend) throws Exception {
        return video("Jar " + tid + " " + pg);
    }

    @Override public String detailContent(List<String> ids) throws Exception { return video("Jar 详情"); }

    @Override public String searchContent(String key, boolean quick) throws Exception { return video(key); }

    @Override public String playerContent(String flag, String id, List<String> vipFlags) throws Exception {
        return new JSONObject().put("parse", 0).put("url", base + "video.mp4")
            .put("header", new JSONObject().put("Referer", base)).toString();
    }
}
