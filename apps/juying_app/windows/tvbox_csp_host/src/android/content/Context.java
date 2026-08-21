package android.content;

public class Context {
    public static final int MODE_PRIVATE = 0;
    private final MemoryPreferences preferences = new MemoryPreferences();
    public Context getApplicationContext() { return this; }
    public SharedPreferences getSharedPreferences(String name, int mode) { return preferences; }

    private static final class MemoryPreferences implements SharedPreferences, SharedPreferences.Editor {
        private final java.util.Map<String, Object> values = new java.util.HashMap<>();
        public java.util.Map<String, ?> getAll() { return java.util.Map.copyOf(values); }
        public String getString(String key, String fallback) { Object value = values.get(key); return value instanceof String ? (String) value : fallback; }
        @SuppressWarnings("unchecked") public java.util.Set<String> getStringSet(String key, java.util.Set<String> fallback) { Object value = values.get(key); return value instanceof java.util.Set ? (java.util.Set<String>) value : fallback; }
        public int getInt(String key, int fallback) { Object value = values.get(key); return value instanceof Number ? ((Number) value).intValue() : fallback; }
        public long getLong(String key, long fallback) { Object value = values.get(key); return value instanceof Number ? ((Number) value).longValue() : fallback; }
        public float getFloat(String key, float fallback) { Object value = values.get(key); return value instanceof Number ? ((Number) value).floatValue() : fallback; }
        public boolean getBoolean(String key, boolean fallback) { Object value = values.get(key); return value instanceof Boolean ? (Boolean) value : fallback; }
        public boolean contains(String key) { return values.containsKey(key); }
        public SharedPreferences.Editor edit() { return this; }
        public SharedPreferences.Editor putString(String key, String value) { values.put(key, value); return this; }
        public SharedPreferences.Editor putStringSet(String key, java.util.Set<String> value) { values.put(key, value); return this; }
        public SharedPreferences.Editor putInt(String key, int value) { values.put(key, value); return this; }
        public SharedPreferences.Editor putLong(String key, long value) { values.put(key, value); return this; }
        public SharedPreferences.Editor putFloat(String key, float value) { values.put(key, value); return this; }
        public SharedPreferences.Editor putBoolean(String key, boolean value) { values.put(key, value); return this; }
        public SharedPreferences.Editor remove(String key) { values.remove(key); return this; }
        public SharedPreferences.Editor clear() { values.clear(); return this; }
        public boolean commit() { return true; }
        public void apply() {}
    }
}
