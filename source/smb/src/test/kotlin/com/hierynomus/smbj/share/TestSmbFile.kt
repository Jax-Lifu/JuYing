package com.hierynomus.smbj.share

import com.hierynomus.msfscc.fileinformation.FileAllInformation
import com.hierynomus.msfscc.fileinformation.FileStandardInformation
import com.hierynomus.mssmb2.SMB2FileId
import com.hierynomus.smbj.common.SmbPath
import java.io.IOException

// SMBJ's File constructor is package-private; keep the offline wire fixture in its package.
class TestSmbFile(share: DiskShare, path: String, private val failInfo: Boolean) :
    File(SMB2FileId(), share, SmbPath("nas", "movies", path)) {
    var closeCalls = 0
    var failClose = false

    override fun getFileInformation(): FileAllInformation {
        if (failInfo) throw IOException("Metadata unavailable")
        val standard = FileStandardInformation::class.java.declaredConstructors.single().apply { isAccessible = true }
            .newInstance(10L, 10L, 1L, false, false)
        return FileAllInformation::class.java.declaredConstructors.single().apply { isAccessible = true }
            .newInstance(null, standard, null, null, null, null, null, null, "movie.mkv") as FileAllInformation
    }

    override fun close() {
        closeCalls++
        if (failClose) throw IOException("Close failed")
    }
}
