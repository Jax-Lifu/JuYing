package com.flytech.juying.core.database

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

@Dao
interface SourceDao {
    @Query("SELECT * FROM sources ORDER BY sortOrder, name")
    fun observeAll(): Flow<List<SourceEntity>>

    @Query("SELECT * FROM sources WHERE id = :id")
    suspend fun get(id: String): SourceEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: SourceEntity)

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertPreset(entity: SourceEntity)

    // 迁移只替换仍与读出快照一致的密文字段，不能覆盖同时发生的编辑或删除。
    @Query("UPDATE sources SET url=:url, username=:username, password=:password, extraJson=:extra WHERE id=:id AND url=:oldUrl AND username IS :oldUsername AND password IS :oldPassword AND extraJson=:oldExtra")
    suspend fun protect(id: String, url: String, username: String?, password: String?, extra: String,
        oldUrl: String, oldUsername: String?, oldPassword: String?, oldExtra: String)

    @Query("DELETE FROM sources WHERE id = :id")
    suspend fun delete(id: String)
}

@Dao
interface HistoryDao {
    @Query("SELECT * FROM history ORDER BY updatedAt DESC LIMIT :limit")
    fun observeRecent(limit: Int): Flow<List<HistoryDbEntity>>

    @Query("SELECT * FROM history WHERE id = :id LIMIT 1")
    suspend fun get(id: String): HistoryDbEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: HistoryDbEntity)

    @Query("DELETE FROM history WHERE id = :id")
    suspend fun delete(id: String)

    @Query("DELETE FROM history")
    suspend fun clear()
}

@Dao
interface FavoriteDao {
    @Query("SELECT * FROM favorites ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<FavoriteEntity>>

    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE id = :id)")
    fun observeIsFavorite(id: String): Flow<Boolean>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(entity: FavoriteEntity)

    @Query("DELETE FROM favorites WHERE id = :id")
    suspend fun delete(id: String)
}
