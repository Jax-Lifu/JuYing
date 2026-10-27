package com.flytech.juying.core.database

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "sources",
    indices = [Index(value = ["sortOrder", "name"])],
)
data class SourceEntity(
    @PrimaryKey val id: String,
    val name: String,
    val type: String,
    val url: String,
    val enabled: Boolean,
    val username: String?,
    val password: String?,
    val extraJson: String = "{}",
    val sortOrder: Int = 0,
)

@Entity(
    tableName = "history",
    indices = [Index(value = ["updatedAt"])],
)
data class HistoryDbEntity(
    @PrimaryKey val id: String,
    val kind: String,
    val sourceId: String,
    val ref: String,
    val title: String,
    val positionMs: Long,
    val durationMs: Long,
    val updatedAt: Long,
    val cover: String? = null,
    @androidx.room.ColumnInfo(defaultValue = "'{}'") val extraJson: String = "{}",
)

@Entity(
    tableName = "favorites",
    indices = [Index(value = ["createdAt"])],
)
data class FavoriteEntity(
    @PrimaryKey val id: String,
    val kind: String,
    val sourceId: String,
    val ref: String,
    val title: String,
    val cover: String?,
    val createdAt: Long,
)
