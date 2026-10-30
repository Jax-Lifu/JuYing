package com.flytech.juying.source.smb

import android.net.Uri
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import com.flytech.juying.core.model.SourceConfig
import com.flytech.juying.core.model.SourceType
import com.hierynomus.msdtyp.AccessMask
import com.hierynomus.msfscc.FileAttributes
import com.hierynomus.msfscc.fileinformation.FileIdBothDirectoryInformation
import com.hierynomus.mssmb2.SMB2CreateDisposition
import com.hierynomus.mssmb2.SMB2CreateOptions
import com.hierynomus.mssmb2.SMB2Dialect
import com.hierynomus.mssmb2.SMB2ShareAccess
import com.hierynomus.smbj.SMBClient
import com.hierynomus.smbj.SmbConfig
import com.hierynomus.smbj.auth.AuthenticationContext
import com.hierynomus.smbj.common.SmbPath
import com.hierynomus.smbj.connection.Connection
import com.hierynomus.smbj.connection.ConnectionContext
import com.hierynomus.smbj.connection.NegotiatedProtocol
import com.hierynomus.smbj.event.SMBEventBus
import com.hierynomus.smbj.paths.PathResolver
import com.hierynomus.smbj.server.ServerList
import com.hierynomus.smbj.session.Session
import com.hierynomus.smbj.share.DiskShare
import com.hierynomus.smbj.share.TestSmbFile
import com.hierynomus.smbj.share.TreeConnect
import java.io.IOException
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SmbConnectionsTest {
    @Test fun changedPasswordCannotReuseAnAuthenticatedShare() {
        val client = TestClient()
        val connections = SmbConnections { client }
        val target = SmbTarget("nas", "movies", "", "user", "correct")
        connections.registerCredentials(target)
        val oldShare = connections.share(target) as TestShare
        connections.registerCredentials(target.copy(password = "wrong"))

        assertThrows(SecurityException::class.java) { connections.share(target.copy(password = "wrong")) }
        assertTrue(oldShare.closed)
        assertTrue(client.connections.first().closed)
        assertTrue(client.connections.last().closed)
        assertEquals(2, client.authentications)
    }

    @Test fun unchangedCredentialsReuseTheShareButDomainAndEmptyPasswordChangesReconnect() {
        val client = TestClient()
        val connections = SmbConnections { client }
        val target = SmbTarget("nas", "movies", "", "user", "correct")
        connections.registerCredentials(target)
        val original = connections.share(target) as TestShare
        connections.registerCredentials(target.copy(basePath = "folder"))
        assertSame(original, connections.share(target.copy(password = "")))
        assertEquals(1, client.authentications)

        val domain = target.copy(domain = "WORKGROUP")
        connections.registerCredentials(domain)
        val replacement = connections.share(domain) as TestShare
        assertTrue(original.closed)
        assertNotSame(original, replacement)
        assertEquals("WORKGROUP", client.lastDomain)

        connections.registerCredentials(domain.copy(password = ""))
        assertThrows(SecurityException::class.java) { connections.share(domain.copy(password = "")) }
        assertTrue(replacement.closed)
        assertEquals(3, client.authentications)
    }

    @Test fun explicitEmptyCredentialsCannotReuseThePasswordlessPlaybackShare() {
        val client = TestClient()
        val connections = SmbConnections { client }
        val target = SmbTarget("nas", "movies", "", "user", "correct", "WORKGROUP")
        val original = connections.share(target, useTargetCredentials = true) as TestShare
        val passwordless = target.copy(password = "", domain = "")

        assertSame(original, connections.share(passwordless))
        assertEquals(1, client.authentications)
        assertThrows(SecurityException::class.java) {
            connections.share(passwordless, useTargetCredentials = true)
        }
        assertTrue(original.closed)
        assertTrue(client.connections.first().closed)
        assertTrue(client.connections.last().closed)
        assertEquals("", client.lastDomain)
        assertEquals(2, client.authentications)
    }

    @Test fun cancellingListingInterruptsReadAndClosesCachedShareAndConnection() = runBlocking {
        val client = TestClient()
        val connections = SmbConnections { client }
        val config = SourceConfig("nas", "Movies", SourceType.SMB, "smb://nas/movies", username = "user", password = "correct")
        val cached = connections.share(SmbTarget.fromConfig(config), useTargetCredentials = true) as TestShare
        val context = RuntimeEnvironment.getApplication()
        val source = SmbSource(connections, SmbNetworkStorage(context, Dispatchers.IO), Dispatchers.IO)
        val listing = async(Dispatchers.IO) { source.list(config, "") }
        try {
            assertTrue(cached.listingStarted.await(2, TimeUnit.SECONDS))
            listing.cancelAndJoin()
            assertTrue(cached.listingInterrupted)
            assertTrue(cached.closed)
            assertTrue(client.connections.single().closed)
        } finally { listing.cancelAndJoin() }
    }

    @Test fun closingPlaybackReleasesEachFileOnceAndKeepsTheConnectionReusable() {
        for (failClose in listOf(false, true)) {
            val client = TestClient()
            val connections = SmbConnections { client }
            val target = SmbTarget("nas", "movies", "", "user", "correct")
            val share = connections.share(target, useTargetCredentials = true) as TestShare
            val source = SmbDataSource(connections)
            val transfers = TransferCounter()
            source.addTransferListener(transfers)
            val request = DataSpec(Uri.parse(target.toPlayUri("movie.mkv")))

            assertEquals(10L, source.open(request))
            val first = share.files.single().also { it.failClose = failClose }
            if (failClose) assertThrows(IOException::class.java) { source.close() } else source.close()
            source.close()

            assertEquals(1, first.closeCalls)
            assertNull(source.uri)
            assertEquals(1, transfers.ended)
            assertFalse(share.closed)
            assertFalse(client.connections.single().closed)
            assertEquals(10L, source.open(request))
            assertEquals(2, share.files.size)
            assertEquals(1, client.authentications)
            source.close()
            assertEquals(1, share.files.last().closeCalls)
            assertEquals(2, transfers.ended)
        }
    }

    @Test fun closingAfterMetadataFailureReleasesTheFileWithoutEndingAnUnstartedTransfer() {
        val client = TestClient()
        val connections = SmbConnections { client }
        val target = SmbTarget("nas", "movies", "", "user", "correct")
        val share = connections.share(target, useTargetCredentials = true) as TestShare
        share.failFileInfo = true
        val source = SmbDataSource(connections)
        val transfers = TransferCounter()
        source.addTransferListener(transfers)

        assertThrows(IOException::class.java) { source.open(DataSpec(Uri.parse(target.toPlayUri("movie.mkv")))) }
        source.close()
        source.close()

        assertEquals(1, share.files.single().closeCalls)
        assertNull(source.uri)
        assertEquals(0, transfers.ended)
    }

    private class TransferCounter : TransferListener {
        var ended = 0
        override fun onTransferInitializing(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
        override fun onTransferStart(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) = Unit
        override fun onBytesTransferred(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean, bytesTransferred: Int) = Unit
        override fun onTransferEnd(source: DataSource, dataSpec: DataSpec, isNetwork: Boolean) { ended++ }
    }

    private class TestClient : SMBClient(config) {
        val connections = mutableListOf<TestConnection>()
        var authentications = 0
        var lastDomain = ""
        override fun connect(hostname: String, port: Int): Connection = TestConnection(this).also(connections::add)
    }

    private class TestConnection(private val owner: TestClient) : Connection(config, owner, SMBEventBus(), ServerList()) {
        var closed = false
        override fun isConnected() = !closed
        override fun close() { closed = true }
        override fun authenticate(auth: AuthenticationContext): Session {
            owner.authentications++
            owner.lastDomain = auth.domain
            if (String(auth.password) != "correct") throw SecurityException("Authentication rejected")
            return object : Session(this, config, auth, null, PathResolver.LOCAL, null, null) {
                override fun connectShare(name: String) = TestShare(this, name)
            }
        }
    }

    private class TestShare(session: Session, name: String) : DiskShare(SmbPath("nas", name),
        TreeConnect(1, SmbPath("nas", name), session, emptySet(), config, context(), null, emptySet(), emptySet()), PathResolver.LOCAL) {
        var closed = false
        var failFileInfo = false
        val files = mutableListOf<TestSmbFile>()
        val listingStarted = CountDownLatch(1)
        var listingInterrupted = false
        override fun isConnected() = !closed
        override fun close() { closed = true }
        override fun openFile(path: String, accessMask: Set<AccessMask>, attributes: Set<FileAttributes>?,
            shareAccess: Set<SMB2ShareAccess>, disposition: SMB2CreateDisposition, options: Set<SMB2CreateOptions>?) =
            TestSmbFile(this, path, failFileInfo).also(files::add)
        override fun list(path: String): MutableList<FileIdBothDirectoryInformation> {
            listingStarted.countDown()
            try { CountDownLatch(1).await(5, TimeUnit.SECONDS) }
            catch (error: InterruptedException) { listingInterrupted = true; throw error }
            return mutableListOf()
        }
    }

    private companion object {
        val config: SmbConfig = SmbConfig.createDefaultConfig()
        // SMBJ exposes no offline negotiated context; only the wire endpoint is replaced in these cache tests.
        fun context(): ConnectionContext = ReflectionHelpers.callConstructor(ConnectionContext::class.java,
            ClassParameter.from(UUID::class.java, UUID.randomUUID()), ClassParameter.from(String::class.java, "nas"),
            ClassParameter.from(Int::class.javaPrimitiveType, 445), ClassParameter.from(SmbConfig::class.java, config)).also {
            ReflectionHelpers.setField(it, "negotiatedProtocol", NegotiatedProtocol(SMB2Dialect.SMB_2_1, 65536, 65536, 65536, false))
        }
    }
}
