#include <jni.h>

#include "juying_cctv_h5e.h"

// The decoder validates and updates one complete segment transactionally.
// No native state survives a seek, cancellation, or change of episode.
namespace {
jint DecodeSegment(JNIEnv *env, jbyteArray segment,
                   int32_t (*decode)(uint8_t *, intptr_t)) {
  if (!segment)
    return -1;
  const jsize size = env->GetArrayLength(segment);
  jbyte *bytes = env->GetByteArrayElements(segment, nullptr);
  if (!bytes)
    return -1;
  const int result = decode(reinterpret_cast<uint8_t *>(bytes), size);
  env->ReleaseByteArrayElements(segment, bytes, result == 0 ? 0 : JNI_ABORT);
  return result;
}
} // namespace

extern "C" JNIEXPORT jint JNICALL
Java_com_flytech_juying_source_cctv_CctvH5eDecoder_decode(
    JNIEnv *env, jobject, jbyteArray segment) {
  return DecodeSegment(env, segment, juying_h5e_decode);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_flytech_juying_source_cctv_CctvH5eDecoder_decodeLive(
    JNIEnv *env, jobject, jbyteArray segment) {
  return DecodeSegment(env, segment, juying_cdrm_decode);
}
