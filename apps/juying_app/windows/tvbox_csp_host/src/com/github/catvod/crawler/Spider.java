package com.github.catvod.crawler;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import android.content.Context;

public abstract class Spider {
    public String siteKey;
    public String homeContent(boolean filter) throws Exception { return ""; }
    public void init(Context context) throws Exception {}
    public void init(Context context, String extend) throws Exception { init(context); }
    public String homeVideoContent() throws Exception { return ""; }
    public String categoryContent(String tid, String page, boolean filter, HashMap<String, String> extend) throws Exception { return ""; }
    public String detailContent(List<String> ids) throws Exception { return ""; }
    public String searchContent(String key, boolean quick) throws Exception { return ""; }
    public String searchContent(String key, boolean quick, String page) throws Exception { return searchContent(key, quick); }
    public String playerContent(String flag, String id, List<String> vipFlags) throws Exception { return ""; }
    public Object[] proxy(Map<String, String> params) throws Exception { return null; }
    public void destroy() {}
}
