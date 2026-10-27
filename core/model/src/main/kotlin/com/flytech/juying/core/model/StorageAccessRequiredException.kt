package com.flytech.juying.core.model

/** Shared storage needs an Android permission grant; retrying credentials cannot resolve this failure. */
class StorageAccessRequiredException : SecurityException("Storage access permission is required")
