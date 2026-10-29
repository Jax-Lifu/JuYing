package com.flytech.juying.source.smb

import android.net.Uri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.BaseDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.smbj.share.File
import dagger.Binds
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.IntoMap
import dagger.multibindings.StringKey
import java.io.IOException
import java.util.EnumSet
import javax.inject.Inject

/**
 * 让 ExoPlayer 通过 smb:// 随机读取局域网 NAS 文件。
 * 针对局域网网络特点进行深度优化：
 * 1. 采用 512KB 内存预读缓冲，消除 ExoPlayer 频繁发起的 8KB~32KB 小包同步网络往返。
 * 2. 复用已打开的 SMB 文件句柄，避免媒体嗅探与拖动定位时反复执行 SMB2 CREATE/CLOSE 握手。
 */
@UnstableApi
class SmbDataSource(private val connections: SmbConnections) : BaseDataSource(/* isNetwork = */ false) {

    private companion object {
        const val PREFETCH_SIZE = 512 * 1024 // 512 KB 预读缓冲区
    }

    private var uri: Uri? = null
    private var file: File? = null
    private var target: SmbTarget? = null
    private var position = 0L
    private var remaining = 0L
    private var opened = false

    // 内存预读缓冲区状态
    private val prefetchBuffer = ByteArray(PREFETCH_SIZE)
    private var prefetchStart = -1L
    private var prefetchLength = 0

    override fun open(dataSpec: DataSpec): Long {
        uri = dataSpec.uri
        transferInitializing(dataSpec)
        val t = SmbTarget.fromPlayUri(dataSpec.uri)

        // 句柄复用：同一文件目标直接调整偏移与剩余长度，避免重复向 NAS 发起 SMB2 CREATE
        if (t == target && file != null) {
            position = dataSpec.position
            val size = file!!.fileInformation.standardInformation.endOfFile
            remaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) dataSpec.length else size - position
            // 检查当前预读缓冲区是否仍覆盖新的 position
            if (position < prefetchStart || position >= prefetchStart + prefetchLength) {
                prefetchStart = -1L
                prefetchLength = 0
            }
            opened = true
            transferStarted(dataSpec)
            return remaining
        }

        // 目标变更或首次打开：释放旧文件并打开新文件
        try {
            file?.close()
        } catch (_: Exception) {}
        file = null
        target = t

        try {
            val share = connections.share(t)
            val f = share.openFile(
                t.basePath,
                EnumSet.of(AccessMask.GENERIC_READ),
                null,
                EnumSet.of(SMB2ShareAccess.FILE_SHARE_READ),
                SMB2CreateDisposition.FILE_OPEN,
                null,
            )
            file = f
            val size = f.fileInformation.standardInformation.endOfFile
            position = dataSpec.position
            remaining = if (dataSpec.length != C.LENGTH_UNSET.toLong()) dataSpec.length else size - position
            prefetchStart = -1L
            prefetchLength = 0
        } catch (e: Exception) {
            connections.invalidate(t)
            throw IOException("SMB open failed: ${e.message}", e)
        }
        opened = true
        transferStarted(dataSpec)
        return remaining
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        if (length == 0) return 0
        if (remaining == 0L) return C.RESULT_END_OF_INPUT
        val currentFile = file ?: throw IOException("SMB file is not open")
        val maxAvailable = minOf(remaining, length.toLong()).toInt()

        // 1. 命中预读缓冲区：直接从内存拷贝，0 网络往返延迟
        if (position >= prefetchStart && position < prefetchStart + prefetchLength) {
            val bufOffset = (position - prefetchStart).toInt()
            val available = minOf(maxAvailable, prefetchLength - bufOffset)
            System.arraycopy(prefetchBuffer, bufOffset, buffer, offset, available)
            position += available
            remaining -= available
            bytesTransferred(available)
            return available
        }

        // 2. 超大单次读取（大于等于预读块）：直读远端
        if (maxAvailable >= PREFETCH_SIZE) {
            val n = try {
                currentFile.read(buffer, position, offset, maxAvailable)
            } catch (e: Exception) {
                target?.let(connections::invalidate)
                throw IOException("SMB read failed: ${e.message}", e)
            }
            if (n < 0) return C.RESULT_END_OF_INPUT
            position += n
            remaining -= n
            bytesTransferred(n)
            return n
        }

        // 3. 小块读取：一次性预读 512KB 填满缓冲区，后续连续小块请求直接命中内存
        val toPrefetch = minOf(PREFETCH_SIZE.toLong(), remaining).toInt()
        val readCount = try {
            currentFile.read(prefetchBuffer, position, 0, toPrefetch)
        } catch (e: Exception) {
            target?.let(connections::invalidate)
            throw IOException("SMB prefetch failed: ${e.message}", e)
        }
        if (readCount <= 0) return C.RESULT_END_OF_INPUT
        prefetchStart = position
        prefetchLength = readCount

        val toCopy = minOf(maxAvailable, readCount)
        System.arraycopy(prefetchBuffer, 0, buffer, offset, toCopy)
        position += toCopy
        remaining -= toCopy
        bytesTransferred(toCopy)
        return toCopy
    }

    override fun getUri(): Uri? = uri

    override fun close() {
        if (opened) {
            opened = false
            transferEnded()
        }
    }
}

/** Samba (SMB) 协议 Media3 DataSource 工厂。 */
@UnstableApi
class SmbDataSourceFactory @Inject constructor(private val connections: SmbConnections) : DataSource.Factory {
    override fun createDataSource(): DataSource = SmbDataSource(connections)
}

/** 按 URI scheme 注册到播放器：新增 NFS/WebDAV 同理，写一个同样的 Module 即可。 */
@Module
@InstallIn(SingletonComponent::class)
abstract class SmbDataSourceModule {
    @UnstableApi
    @Binds @IntoMap @StringKey("smb")
    abstract fun smb(factory: SmbDataSourceFactory): DataSource.Factory
}
