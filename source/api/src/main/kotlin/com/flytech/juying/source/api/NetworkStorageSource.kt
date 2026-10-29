package com.flytech.juying.source.api

import com.flytech.juying.core.model.NetworkStorageDevice
import com.flytech.juying.core.model.SourceConfig
import kotlinx.coroutines.flow.Flow

/**
 * 局域网网络存储数据源扩展契约（SMB、NFS、WebDAV 等）。
 *
 * **What**: 定义局域网存储设备的搜索发现、手动录入、共享名枚举及草稿配置生成能力。
 *
 * **Why**: 将用户发起的主动搜索与会话清理生命周期统一约束，调用方取消协程即释放底层网络套接字或未闭合连接。
 */
interface NetworkStorageSource : SourceProvider {

    /**
     * 发现局域网内的网络存储设备。
     * 收集流停止或取消时，必须立即释放后台发现资源。
     *
     * @return 动态发出的网络存储设备流（去重后）
     */
    fun discoverDevices(): Flow<NetworkStorageDevice>

    /**
     * 手动输入服务器地址创建设备草稿。
     * 仅接收主机地址或 IP，严禁传入共享路径或认证凭据。
     *
     * @param address 主机名或 IP 地址
     */
    fun manualDevice(address: String): NetworkStorageDevice

    /**
     * 枚举指定网络存储设备上当前凭据可见的所有共享目录（Share）。
     *
     * @param device 目标设备
     * @param username 用户名（留空表示匿名）
     * @param password 访问密码（可为空）
     * @param domain 工作组或域（如 WORKGROUP）
     * @return 共享名称列表（如 ["movies", "media"]）
     */
    suspend fun shares(device: NetworkStorageDevice, username: String, password: String, domain: String): List<String>

    /**
     * 构建未持久化的 [SourceConfig] 配置草稿。
     * 调用方在将此草稿存入数据库前，必须通过测试连接核实读取权限。
     *
     * @param device 存储设备
     * @param share 选定的共享目录名称
     * @param username 认证用户名
     * @param password 认证密码
     * @param domain 工作组/域
     */
    fun configuration(device: NetworkStorageDevice, share: String, username: String, password: String, domain: String): SourceConfig

    /**
     * 对给定的服务器 IP 或主机地址解析友好设备名（如通过 NetBIOS 或反向 DNS）。
     * 若无法解析或不支持，返回 null。
     *
     * @param address IP 或主机地址字符串
     * @return 解析成功的主机名，或 null
     */
    fun resolveHostname(address: String): String? = null
}
