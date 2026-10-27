package com.flytech.juying

import android.database.sqlite.SQLiteDatabase
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.flytech.juying.core.database.DatabaseModule
import com.flytech.juying.core.database.JuyingDatabase
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryMigrationTest {
    @Test fun addingArtworkPreservesSourcesAndPlaybackPosition() = runBlocking {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val name = "ui-migration-test.db"
        context.deleteDatabase(name)
        try {
            SQLiteDatabase.openOrCreateDatabase(context.getDatabasePath(name), null).use { db ->
                db.execSQL("CREATE TABLE sources (id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL, url TEXT NOT NULL, enabled INTEGER NOT NULL, username TEXT, password TEXT, extraJson TEXT NOT NULL, sortOrder INTEGER NOT NULL)")
                db.execSQL("CREATE INDEX index_sources_sortOrder_name ON sources(sortOrder, name)")
                db.execSQL("CREATE TABLE history (id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, sourceId TEXT NOT NULL, ref TEXT NOT NULL, title TEXT NOT NULL, positionMs INTEGER NOT NULL, durationMs INTEGER NOT NULL, updatedAt INTEGER NOT NULL)")
                db.execSQL("CREATE INDEX index_history_updatedAt ON history(updatedAt)")
                db.execSQL("CREATE TABLE favorites (id TEXT NOT NULL PRIMARY KEY, kind TEXT NOT NULL, sourceId TEXT NOT NULL, ref TEXT NOT NULL, title TEXT NOT NULL, cover TEXT, createdAt INTEGER NOT NULL)")
                db.execSQL("CREATE INDEX index_favorites_createdAt ON favorites(createdAt)")
                db.execSQL("INSERT INTO sources VALUES ('saved', 'Saved source', 'TVBOX', 'https://example.test', 1, NULL, NULL, '{}', 0)")
                db.execSQL("INSERT INTO history VALUES ('saved-play', 'VOD', 'saved', 'episode', 'Saved title', 45000, 90000, 10)")
                db.version = 2
            }
            val db = Room.databaseBuilder(context, JuyingDatabase::class.java, name)
                .addMigrations(DatabaseModule.MIGRATION_2_3, DatabaseModule.MIGRATION_3_4).build()
            try {
                val old = db.historyDao().get("saved-play")!!
                assertEquals(45000L, old.positionMs)
                assertNull(old.cover)
                assertEquals("{}", old.extraJson)
                assertEquals("Saved source", db.sourceDao().get("saved")!!.name)
                db.historyDao().upsert(old.copy(cover = "https://example.test/cover.jpg"))
                assertEquals("https://example.test/cover.jpg", db.historyDao().get("saved-play")!!.cover)
                val repository = com.flytech.juying.core.data.DefaultHistoryRepository(db.historyDao())
                repository.record(repository.get("saved-play")!!.copy(extra = mapOf("itemId" to "album", "episodeTitle" to "Episode 2")))
                assertEquals("album", repository.get("saved-play")!!.extra["itemId"])
            } finally { db.close() }
        } finally { context.deleteDatabase(name) }
    }
}
