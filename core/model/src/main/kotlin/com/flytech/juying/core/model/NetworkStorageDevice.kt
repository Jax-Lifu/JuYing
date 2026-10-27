package com.flytech.juying.core.model

/** A discovered server is not a saved source until a readable share has been selected. */
data class NetworkStorageDevice(
    val type: SourceType,
    val name: String,
    val host: String,
    val port: Int,
)
