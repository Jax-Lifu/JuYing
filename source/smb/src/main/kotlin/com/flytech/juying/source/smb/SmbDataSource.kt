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

/** 让 ExoPlayer 通过 smb:// 随机读取远端文件（支持拖动/断点）。 */
@UnstableApi
class SmbDataSource(private val connections: SmbConnections) : BaseDataSource(/* isNetwork = */ true) {

    private var uri: Uri? = null
    private var file: File? = null
    private var target: SmbTarget? = null
    private var position = 0L
    private var remaining = 0L
    private var opened = false

    override fun open(dataSpec: DataSpec): Long {
        uri = dataSpec.uri
        transferInitializing(dataSpec)
        val t = SmbTarget.fromPlayUri(dataSpec.uri).also { target = it }
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
        val toRead = minOf(remaining, length.toLong()).toInt()
        val n = try {
            currentFile.read(buffer, position, offset, toRead)
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

    override fun getUri(): Uri? = uri

    override fun close() {
        uri = null
        try {
            file?.close()
        } finally {
            file = null
            if (opened) {
                opened = false
                transferEnded()
            }
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
