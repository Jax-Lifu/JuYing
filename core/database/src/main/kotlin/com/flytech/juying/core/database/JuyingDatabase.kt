package com.flytech.juying.core.database

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Database(
    entities = [SourceEntity::class, HistoryDbEntity::class, FavoriteEntity::class],
    version = 4,
    exportSchema = false,
)
abstract class JuyingDatabase : RoomDatabase() {
    abstract fun sourceDao(): SourceDao
    abstract fun historyDao(): HistoryDao
    abstract fun favoriteDao(): FavoriteDao
}

@Module
@InstallIn(SingletonComponent::class)
object DatabaseModule {
    val MIGRATION_2_3 = object : androidx.room.migration.Migration(2, 3) {
        override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE history ADD COLUMN cover TEXT")
        }
    }
    val MIGRATION_3_4 = object : androidx.room.migration.Migration(3, 4) {
        override fun migrate(db: androidx.sqlite.db.SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE history ADD COLUMN extraJson TEXT NOT NULL DEFAULT '{}'")
        }
    }
    @Provides
    @Singleton
    fun database(@ApplicationContext context: Context): JuyingDatabase =
        Room.databaseBuilder(context, JuyingDatabase::class.java, "juying.db")
            .addMigrations(MIGRATION_2_3, MIGRATION_3_4)
            .build()

    @Provides fun sourceDao(db: JuyingDatabase) = db.sourceDao()
    @Provides fun historyDao(db: JuyingDatabase) = db.historyDao()
    @Provides fun favoriteDao(db: JuyingDatabase) = db.favoriteDao()
}
