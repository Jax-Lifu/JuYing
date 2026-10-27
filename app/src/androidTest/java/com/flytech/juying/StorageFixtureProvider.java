package com.flytech.juying;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.res.AssetFileDescriptor;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.provider.DocumentsContract.Document;
import java.io.File;
import java.io.FileNotFoundException;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/** Uses only Android and Java APIs because the separate test APK process has no Kotlin runtime. */
public final class StorageFixtureProvider extends ContentProvider {
    private static final Entry ROOT = new Entry("root", "Storage fixture", Document.MIME_TYPE_DIR);
    private static final Entry FOLDER = new Entry("root/Movies", "Movies", Document.MIME_TYPE_DIR);
    private static final Entry VIDEO = new Entry("root/Movies/test-pattern.mp4", "test-pattern.mp4", "video/mp4");
    private static final Entry SUBTITLE = new Entry("root/Movies/test-pattern.zh.srt", "test-pattern.zh.srt", "application/x-subrip");
    private static final Entry[] ENTRIES = { ROOT, FOLDER, VIDEO, SUBTITLE };

    @Override public boolean onCreate() { return true; }

    @Override public Cursor query(Uri uri, String[] projection, String selection, String[] args, String order) {
        String id = DocumentsContract.getDocumentId(uri);
        Entry[] entries;
        if ("children".equals(uri.getLastPathSegment())) {
            if (ROOT.id.equals(id)) entries = new Entry[] { FOLDER };
            else if (FOLDER.id.equals(id)) entries = new Entry[] { VIDEO, SUBTITLE };
            else throw new IllegalArgumentException("Unknown directory");
        } else {
            Entry entry = findEntry(id);
            if (entry == null) throw new IllegalArgumentException("Unknown document");
            entries = new Entry[] { entry };
        }
        String[] columns = projection != null ? projection : new String[] {
            Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE
        };
        MatrixCursor cursor = new MatrixCursor(columns);
        for (Entry entry : entries) {
            Object[] row = new Object[columns.length];
            for (int i = 0; i < columns.length; i++) {
                switch (columns[i]) {
                    case Document.COLUMN_DOCUMENT_ID: row[i] = entry.id; break;
                    case Document.COLUMN_DISPLAY_NAME: row[i] = entry.name; break;
                    case Document.COLUMN_MIME_TYPE: row[i] = entry.mime; break;
                    case Document.COLUMN_SIZE:
                    case Document.COLUMN_LAST_MODIFIED: row[i] = 0L; break;
                    default: row[i] = null;
                }
            }
            cursor.addRow(row);
        }
        return cursor;
    }

    @Override public AssetFileDescriptor openAssetFile(Uri uri, String mode) throws FileNotFoundException {
        if (!"r".equals(mode)) throw new FileNotFoundException("Read only");
        Context context = getContext();
        if (context == null) throw new FileNotFoundException("Provider unavailable");
        String id = DocumentsContract.getDocumentId(uri);
        try {
            if (VIDEO.id.equals(id)) return context.getAssets().openFd("test-pattern.mp4");
            if (SUBTITLE.id.equals(id)) {
                File file = new File(context.getCacheDir(), "storage-fixture.zh.srt");
                try (FileOutputStream output = new FileOutputStream(file)) {
                    output.write("1\n00:00:00,000 --> 00:00:07,000\nStorage subtitle fixture\n".getBytes(StandardCharsets.UTF_8));
                }
                return new AssetFileDescriptor(ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY), 0, file.length());
            }
        } catch (IOException error) {
            FileNotFoundException failure = new FileNotFoundException(error.getMessage());
            failure.initCause(error);
            throw failure;
        }
        throw new FileNotFoundException("Unknown document");
    }

    @Override public String getType(Uri uri) {
        Entry entry = findEntry(DocumentsContract.getDocumentId(uri));
        return entry == null ? null : entry.mime;
    }

    @Override public Uri insert(Uri uri, ContentValues values) { throw new UnsupportedOperationException("Read only"); }
    @Override public int delete(Uri uri, String selection, String[] args) { throw new UnsupportedOperationException("Read only"); }
    @Override public int update(Uri uri, ContentValues values, String selection, String[] args) { throw new UnsupportedOperationException("Read only"); }

    private static Entry findEntry(String id) {
        for (Entry entry : ENTRIES) if (entry.id.equals(id)) return entry;
        return null;
    }

    private static final class Entry {
        final String id;
        final String name;
        final String mime;

        Entry(String id, String name, String mime) {
            this.id = id;
            this.name = name;
            this.mime = mime;
        }
    }
}
