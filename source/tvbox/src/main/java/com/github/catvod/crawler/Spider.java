package com.github.catvod.crawler;

import android.content.Context;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * TVBox 爬虫 jar 兼容基类。包名/类名/方法签名必须与生态保持一致，
 * 第三方 jar（如 csp_XXX）会通过反射继承并调用它。
 * 参考实现：FongMi/TV（GPL-3.0，与本项目协议兼容）。
 */
public abstract class Spider {

    /** 与 CatVod JAR 保持静态 ABI；未配置 DoH 时沿用系统 DNS。 */
    public static okhttp3.Dns safeDns() {
        return okhttp3.Dns.SYSTEM;
    }

    public void init(Context context) throws Exception {
    }

    public void init(Context context, String extend) throws Exception {
        init(context);
    }

    public String homeContent(boolean filter) throws Exception {
        return "";
    }

    public String homeVideoContent() throws Exception {
        return "";
    }

    public String categoryContent(String tid, String pg, boolean filter, HashMap<String, String> extend) throws Exception {
        return "";
    }

    public String detailContent(List<String> ids) throws Exception {
        return "";
    }

    public String searchContent(String key, boolean quick) throws Exception {
        return "";
    }

    public String searchContent(String key, boolean quick, String pg) throws Exception {
        return "1".equals(pg) ? searchContent(key, quick) : "{\"list\":[]}";
    }

    public String playerContent(String flag, String id, List<String> vipFlags) throws Exception {
        return "";
    }

    public String liveContent(String url) throws Exception {
        return "";
    }

    public boolean manualVideoCheck() throws Exception {
        return false;
    }

    public boolean isVideoFormat(String url) throws Exception {
        return false;
    }

    public Object[] proxyLocal(Map<String, String> params) throws Exception {
        return null;
    }

    public void destroy() {
    }
}
