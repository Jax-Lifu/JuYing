package com.github.catvod.spider;

import android.content.Context;

import com.github.catvod.crawler.Spider;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.HashMap;
import java.util.List;

/** Locally compiled test code; all playback URLs point to the test-owned loopback server. */
public class Fixture extends Spider {
    private String origin;
    private String label;

    @Override
    public void init(Context context, String extend) throws Exception {
        if (!Init.ready) throw new IllegalStateException("Bundle init has not completed");
        // Resolve the host's externally linked HTTP ABI without issuing a network request.
        if (client().dispatcher().getMaxRequests() <= 0 || safeDns() == null) {
            throw new IllegalStateException("Host HTTP ABI is unavailable");
        }
        JSONObject config = new JSONObject(extend);
        origin = config.getString("origin");
        label = config.getString("label");
    }

    @Override
    public String homeContent(boolean filter) throws Exception {
        return new JSONObject().put("class", new JSONArray().put(new JSONObject()
                .put("type_id", "fixture").put("type_name", label))).toString();
    }

    @Override
    public String categoryContent(String tid, String page, boolean filter,
            HashMap<String, String> extend) throws Exception {
        return new JSONObject().put("list", new JSONArray().put(card(label))).toString();
    }

    @Override
    public String searchContent(String keyword, boolean quick) throws Exception {
        return new JSONObject().put("list", new JSONArray().put(card(keyword))).toString();
    }

    @Override
    public String detailContent(List<String> ids) throws Exception {
        JSONObject card = card(label)
                .put("vod_play_from", "fixture")
                .put("vod_play_url", "第1集$ep1#第2集$ep2");
        return new JSONObject().put("list", new JSONArray().put(card)).toString();
    }

    @Override
    public String playerContent(String flag, String id, List<String> vipFlags) throws Exception {
        return new JSONObject().put("parse", 1)
                .put("url", origin + "/player.html?episode=" + id)
                .put("header", new JSONObject()
                        .put("X-Source", label)
                        .put("X-Vip-Flags", String.join(",", vipFlags)))
                .toString();
    }

    private JSONObject card(String name) throws Exception {
        return new JSONObject().put("vod_id", "fixture-vod").put("vod_name", name);
    }
}
