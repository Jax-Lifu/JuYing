package com.github.catvod.crawler;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

/** The host dispatches the paged signature even when a legacy JAR implements only two arguments. */
public class SpiderSearchTest {
    @Test
    public void pagedEntryDelegatesToLegacySearch() throws Exception {
        Spider spider = new Spider() {
            @Override
            public String searchContent(String key, boolean quick) {
                return key + ":" + quick;
            }
        };

        assertEquals("fixture:false", spider.searchContent("fixture", false, "1"));
    }

    @Test
    public void pagedOverrideRetainsRequestedPage() throws Exception {
        Spider spider = new Spider() {
            @Override
            public String searchContent(String key, boolean quick, String page) {
                return key + ":" + page;
            }
        };

        assertEquals("fixture:3", spider.searchContent("fixture", false, "3"));
    }
}
