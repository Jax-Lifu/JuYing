package com.flytech.juying.source.smb

import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress

/**
 * SMB / Samba 网络存储主机名解析器。
 *
 * **What**: 针对局域网内仅暴露 IP 地址的 SMB 服务器，通过 NetBIOS 节点状态查询（RFC 1002 UDP 137 端口）
 * 与 DNS 反向解析双重机制，提取出友好的设备机器名（如 `DISKSTATION`、`DESKTOP-ABC`）。
 *
 * **Why**: 局域网 mDNS/NSD 发现或用户手动输入 IP 时，界面仅显示裸 IP 对用户不友好；
 * NetBIOS 节点状态查询是 Windows 文件共享及大多数 NAS（Synology、QNAP、TrueNAS）最兼容的主机名发现协议。
 */
internal object SmbHostResolver {

    /**
     * RFC 1002 节点状态请求包（Node Status Request）。
     * 查询通配符主机名 `*` (被 NetBIOS 半字节编码为 32 个字节的 'CKAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')。
     */
    private val NETBIOS_REQUEST = byteArrayOf(
        0x82.toByte(), 0x28.toByte(), 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x20, 0x43, 0x4B, 0x41,
        0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
        0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
        0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41, 0x41,
        0x41, 0x41, 0x41, 0x41, 0x41, 0x00, 0x00, 0x21,
        0x00, 0x01
    )

    private const val NETBIOS_PORT = 137
    private const val DEFAULT_TIMEOUT_MS = 500

    /**
     * 解析指定主机名或 IP 地址。
     *
     * @param host 待解析的主机名或 IP（支持 IPv4 / IPv6，自动去除方括号）
     * @param timeoutMs NetBIOS UDP 请求超时时间（默认 500ms）
     * @return 解析成功返回友好的主机名；若无法解析或本身为非 IP 主机名，则原样返回
     */
    fun resolve(host: String, timeoutMs: Int = DEFAULT_TIMEOUT_MS): String {
        val trimmed = host.trim().removeSurrounding("[", "]")
        if (!isIpAddress(trimmed)) return trimmed

        // 1. NetBIOS node status query on port 137 (fastest & most accurate for SMB / Samba / Windows)
        queryNetBios(trimmed, timeoutMs)?.let { return it }

        // 2. Fallback to DNS reverse lookup
        queryReverseDns(trimmed)?.let { return it }

        return trimmed
    }

    /**
     * 向目标 IP 发送 RFC 1002 UDP 节点状态查询并解析响应。
     */
    internal fun queryNetBios(host: String, timeoutMs: Int = DEFAULT_TIMEOUT_MS): String? {
        return runCatching {
            DatagramSocket().use { socket ->
                socket.soTimeout = timeoutMs
                val target = InetSocketAddress(host, NETBIOS_PORT)
                socket.send(DatagramPacket(NETBIOS_REQUEST, NETBIOS_REQUEST.size, target))

                val buffer = ByteArray(1024)
                val packet = DatagramPacket(buffer, buffer.size)
                socket.receive(packet)

                parseNetBiosNames(buffer, packet.length)
            }
        }.getOrNull()
    }

    /**
     * 解析 NetBIOS 节点状态响应包中的名字表。
     *
     * 响应包偏移说明：
     * - 0..55: NetBIOS Header 及 Answer RDATA 前缀
     * - 56: 名字数量 (NUM_NAMES, 1 字节)
     * - 57 起每 18 字节为一个条目: 15 字节名称 + 1 字节类型 + 2 字节 Flags (最高位标识是否为组名)
     *
     * 优先匹配类型为 0x20 (File Server service) 或 0x00 (Workstation/Redirector service) 的唯一名称。
     */
    internal fun parseNetBiosNames(buffer: ByteArray, length: Int): String? {
        if (length < 57) return null
        val numNames = buffer[56].toInt() and 0xFF
        var candidate: String? = null
        for (i in 0 until numNames) {
            val offset = 57 + i * 18
            if (offset + 18 > length) break
            val type = buffer[offset + 15].toInt() and 0xFF
            val flags = buffer[offset + 16].toInt() and 0xFF
            val isGroup = (flags and 0x80) != 0
            if (!isGroup) {
                val name = String(buffer, offset, 15, Charsets.US_ASCII).trim { it <= ' ' || it == '\u0000' }
                if (name.isNotEmpty() && !name.startsWith("__MSBROWSE__")) {
                    if (type == 0x20 || type == 0x00) {
                        return name
                    }
                    if (candidate == null) candidate = name
                }
            }
        }
        return candidate
    }

    /**
     * 标准 DNS 反向指针查询（PTR）。
     */
    private fun queryReverseDns(host: String): String? {
        return runCatching {
            val address = InetAddress.getByName(host)
            val hostName = address.hostName
            if (!hostName.isNullOrBlank() && hostName != host) hostName else null
        }.getOrNull()
    }

    /**
     * 判断文本是否为有效的 IPv4 或 IPv6 格式。
     */
    fun isIpAddress(text: String): Boolean {
        val s = text.trim().removeSurrounding("[", "]")
        val parts = s.split('.')
        if (parts.size == 4 && parts.all { p -> p.toIntOrNull()?.let { it in 0..255 } == true }) {
            return true
        }
        if (':' in s && s.all { it.isDigit() || it in 'a'..'f' || it in 'A'..'F' || it == ':' }) {
            return true
        }
        return false
    }
}
