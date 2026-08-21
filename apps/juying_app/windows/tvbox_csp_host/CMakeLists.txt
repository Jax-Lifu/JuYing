include(FetchContent)
find_package(Java REQUIRED COMPONENTS Development)
find_program(JLINK_EXECUTABLE jlink HINTS "$ENV{JAVA_HOME}/bin" REQUIRED)

FetchContent_Declare(
  dex2jar_bundle
  URL https://github.com/pxb1988/dex2jar/releases/download/v2.4/dex-tools-v2.4.zip
  URL_HASH SHA256=ee7c45eb3c1d2474a6145d8d447e651a736a22d9664b6d3d3be5a5a817dda23a
)
FetchContent_MakeAvailable(dex2jar_bundle)

set(CSP_DOWNLOAD_DIR "${CMAKE_CURRENT_BINARY_DIR}/downloads")
file(MAKE_DIRECTORY "${CSP_DOWNLOAD_DIR}")
function(csp_download NAME URL HASH)
  if(NOT EXISTS "${CSP_DOWNLOAD_DIR}/${NAME}")
    file(DOWNLOAD "${URL}" "${CSP_DOWNLOAD_DIR}/${NAME}"
      EXPECTED_HASH "SHA256=${HASH}" TLS_VERIFY ON SHOW_PROGRESS)
  endif()
endfunction()

csp_download(android-json.jar
  https://repo1.maven.org/maven2/com/vaadin/external/google/android-json/0.0.20131108.vaadin1/android-json-0.0.20131108.vaadin1.jar
  dfb7bae2f404cfe0b72b4d23944698cb716b7665171812a0a4d0f5926c0fac79)
csp_download(okhttp.jar
  https://repo1.maven.org/maven2/com/squareup/okhttp3/okhttp/4.12.0/okhttp-4.12.0.jar
  b1050081b14bb7a3a7e55a4d3ef01b5dcfabc453b4573a4fc019767191d5f4e0)
csp_download(okio.jar
  https://repo1.maven.org/maven2/com/squareup/okio/okio-jvm/3.6.0/okio-jvm-3.6.0.jar
  67543f0736fc422ae927ed0e504b98bc5e269fda0d3500579337cb713da28412)
csp_download(kotlin-stdlib.jar
  https://repo1.maven.org/maven2/org/jetbrains/kotlin/kotlin-stdlib/1.9.10/kotlin-stdlib-1.9.10.jar
  55e989c512b80907799f854309f3bc7782c5b3d13932442d0379d5c472711504)
csp_download(gson.jar
  https://repo1.maven.org/maven2/com/google/code/gson/gson/2.10.1/gson-2.10.1.jar
  4241c14a7727c34feea6507ec801318a3d4a90f070e4525681079fb94ee4c593)

set(CSP_BUNDLE_DIR "${CMAKE_CURRENT_BINARY_DIR}/bundle")
file(GLOB_RECURSE CSP_JAVA_SOURCES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/src/*.java")
add_custom_command(
  OUTPUT "${CSP_BUNDLE_DIR}/.ready"
  COMMAND ${CMAKE_COMMAND} -E rm -rf "${CSP_BUNDLE_DIR}"
  COMMAND ${CMAKE_COMMAND} -E make_directory "${CSP_BUNDLE_DIR}/classes" "${CSP_BUNDLE_DIR}/lib" "${CSP_BUNDLE_DIR}/dex2jar"
  COMMAND "${Java_JAVAC_EXECUTABLE}" -encoding UTF-8
    -cp "${CSP_DOWNLOAD_DIR}/android-json.jar"
    -d "${CSP_BUNDLE_DIR}/classes" ${CSP_JAVA_SOURCES}
  COMMAND "${JLINK_EXECUTABLE}" --add-modules java.base,java.logging,java.naming,java.security.jgss,jdk.crypto.ec,jdk.zipfs
    --strip-debug --no-header-files --no-man-pages
    --output "${CSP_BUNDLE_DIR}/runtime"
  COMMAND ${CMAKE_COMMAND} -E copy_directory "${dex2jar_bundle_SOURCE_DIR}" "${CSP_BUNDLE_DIR}/dex2jar"
  COMMAND ${CMAKE_COMMAND} -E copy
    "${CSP_DOWNLOAD_DIR}/android-json.jar"
    "${CSP_DOWNLOAD_DIR}/okhttp.jar"
    "${CSP_DOWNLOAD_DIR}/okio.jar"
    "${CSP_DOWNLOAD_DIR}/kotlin-stdlib.jar"
    "${CSP_DOWNLOAD_DIR}/gson.jar"
    "${CSP_BUNDLE_DIR}/lib"
  COMMAND ${CMAKE_COMMAND} -E touch "${CSP_BUNDLE_DIR}/.ready"
  DEPENDS ${CSP_JAVA_SOURCES}
  VERBATIM)

add_custom_target(juying_tvbox_csp_host ALL DEPENDS "${CSP_BUNDLE_DIR}/.ready")
