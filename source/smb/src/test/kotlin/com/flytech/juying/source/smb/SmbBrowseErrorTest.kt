package com.flytech.juying.source.smb

import com.hierynomus.mserref.NtStatus
import com.hierynomus.mssmb2.SMBApiException
import com.hierynomus.mssmb2.SMB2MessageCommandCode
import java.io.FileNotFoundException
import org.junit.Assert.*
import org.junit.Test

class SmbBrowseErrorTest {
    @Test fun onlyMissingPathsAllowRecovery() {
        fun failure(status: NtStatus) = SMBApiException(status.value, SMB2MessageCommandCode.SMB2_QUERY_DIRECTORY, RuntimeException())
        assertTrue(failure(NtStatus.STATUS_OBJECT_PATH_NOT_FOUND).asBrowseException() is FileNotFoundException)
        assertTrue(failure(NtStatus.STATUS_LOGON_FAILURE).asBrowseException() is SecurityException)
        val disconnected = failure(NtStatus.STATUS_CONNECTION_DISCONNECTED)
        assertSame(disconnected, disconnected.asBrowseException())
    }
}
