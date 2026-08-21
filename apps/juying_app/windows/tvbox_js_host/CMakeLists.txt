include(FetchContent)

# 固定 QuickJS 提交，避免远端脚本运行时随构建日期漂移。
FetchContent_Declare(
  quickjs
  GIT_REPOSITORY https://github.com/quickjs-ng/quickjs.git
  GIT_TAG bbe0480a68c664d7737eecde260fd47224b2c0d6
  GIT_SHALLOW TRUE
)
set(QJS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(QJS_BUILD_LIBC OFF CACHE BOOL "" FORCE)
set(BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(BUILD_CLI OFF CACHE BOOL "" FORCE)
set(BUILD_QJSC OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(quickjs)

if(MSVC)
  foreach(tgt qjs qjs-libc qjsc api-test run-test262 lre-test function_source)
    if(TARGET ${tgt})
      set_target_properties(${tgt} PROPERTIES
        VS_GLOBAL_VcpkgApplocalDeps "false"
        VS_GLOBAL_VcpkgEnabled "false"
      )
      target_compile_options(${tgt} PRIVATE
        /w
        /wd4146 /wd4668 /wd4132 /wd4098 /wd4127 /wd4334 /wd4702 /wd4701 /wd4703
      )
    endif()
  endforeach()
endif()

add_executable(juying_tvbox_js_host "main.cpp")
target_compile_features(juying_tvbox_js_host PRIVATE cxx_std_17)
target_compile_definitions(juying_tvbox_js_host PRIVATE
  NOMINMAX WIN32_LEAN_AND_MEAN UNICODE _UNICODE)
target_compile_options(juying_tvbox_js_host PRIVATE /W4 /EHsc /utf-8)
if(MSVC)
  set_target_properties(juying_tvbox_js_host PROPERTIES
    VS_GLOBAL_VcpkgApplocalDeps "false"
    VS_GLOBAL_VcpkgEnabled "false"
  )
endif()
target_link_libraries(juying_tvbox_js_host PRIVATE
  qjs winhttp.lib ws2_32.lib shlwapi.lib)
