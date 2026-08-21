#include <quickjs.h>

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winhttp.h>
#include <shlwapi.h>

#include <algorithm>
#include <chrono>
#include <cstring>
#include <cstdint>
#include <cwctype>
#include <iostream>
#include <iterator>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

constexpr size_t kMemoryLimit = 96 * 1024 * 1024;
constexpr size_t kStackLimit = 2 * 1024 * 1024;
constexpr size_t kMaxResponseBytes = 2 * 1024 * 1024;
constexpr int kMaxRequests = 32;
constexpr int kMaxHosts = 12;
constexpr auto kDeadline = std::chrono::seconds(15);

struct HostState {
  std::chrono::steady_clock::time_point deadline;
  HINTERNET session = nullptr;
  int request_count = 0;
  std::set<std::wstring> hosts;
  std::string error;

  ~HostState() {
    if (session != nullptr) WinHttpCloseHandle(session);
  }
};

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return {};
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                       value.data(), static_cast<int>(value.size()),
                                       nullptr, 0);
  if (size <= 0) throw std::runtime_error("字符串不是有效 UTF-8");
  std::wstring output(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, value.data(),
                      static_cast<int>(value.size()), output.data(), size);
  return output;
}

std::string WideToUtf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                       static_cast<int>(value.size()), nullptr,
                                       0, nullptr, nullptr);
  std::string output(size, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      output.data(), size, nullptr, nullptr);
  return output;
}

std::string JsonQuote(const std::string& value) {
  std::ostringstream out;
  out << '"';
  for (const unsigned char c : value) {
    switch (c) {
      case '"': out << "\\\""; break;
      case '\\': out << "\\\\"; break;
      case '\b': out << "\\b"; break;
      case '\f': out << "\\f"; break;
      case '\n': out << "\\n"; break;
      case '\r': out << "\\r"; break;
      case '\t': out << "\\t"; break;
      default:
        if (c < 0x20) {
          const char hex[] = "0123456789abcdef";
          out << "\\u00" << hex[c >> 4] << hex[c & 15];
        } else {
          out << static_cast<char>(c);
        }
    }
  }
  out << '"';
  return out.str();
}

std::string JsString(JSContext* ctx, JSValueConst value) {
  const char* text = JS_ToCString(ctx, value);
  if (text == nullptr) throw std::runtime_error("JavaScript 字符串转换失败");
  std::string result(text);
  JS_FreeCString(ctx, text);
  return result;
}

std::string PropertyString(JSContext* ctx, JSValueConst object,
                           const char* name, bool required = true) {
  JSValue value = JS_GetPropertyStr(ctx, object, name);
  if (JS_IsException(value)) throw std::runtime_error("读取插件请求字段失败");
  if (JS_IsUndefined(value) || JS_IsNull(value)) {
    JS_FreeValue(ctx, value);
    if (required) throw std::runtime_error(std::string("缺少字段：") + name);
    return {};
  }
  std::string result = JsString(ctx, value);
  JS_FreeValue(ctx, value);
  return result;
}

std::string Stringify(JSContext* ctx, JSValueConst value) {
  JSValue json = JS_JSONStringify(ctx, value, JS_UNDEFINED, JS_UNDEFINED);
  if (JS_IsException(json)) throw std::runtime_error("JSON 序列化失败");
  std::string result = JS_IsUndefined(json) ? "null" : JsString(ctx, json);
  JS_FreeValue(ctx, json);
  return result;
}

bool IsPrivateAddress(const sockaddr* address) {
  if (address->sa_family == AF_INET) {
    const auto* ipv4 = reinterpret_cast<const sockaddr_in*>(address);
    const uint32_t ip = ntohl(ipv4->sin_addr.s_addr);
    const uint8_t a = static_cast<uint8_t>(ip >> 24);
    const uint8_t b = static_cast<uint8_t>(ip >> 16);
    return a == 0 || a == 10 || a == 127 ||
           (a == 169 && b == 254) || (a == 172 && b >= 16 && b <= 31) ||
           (a == 192 && b == 168) || a >= 224;
  }
  if (address->sa_family == AF_INET6) {
    const auto* ipv6 = reinterpret_cast<const sockaddr_in6*>(address);
    const uint8_t* bytes = ipv6->sin6_addr.u.Byte;
    const bool loopback = std::all_of(bytes, bytes + 15,
                                      [](uint8_t byte) { return byte == 0; }) &&
                          bytes[15] == 1;
    return loopback || (bytes[0] & 0xfe) == 0xfc ||
           (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) ||
           bytes[0] == 0xff;
  }
  return true;
}

void ValidatePublicHost(const std::wstring& host) {
  if (host.empty()) throw std::runtime_error("URL 缺少主机名");
  std::wstring lowered = host;
  std::transform(lowered.begin(), lowered.end(), lowered.begin(), towlower);
  if (lowered == L"localhost") throw std::runtime_error("禁止访问本机地址");

  ADDRINFOW hints{};
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;
  ADDRINFOW* result = nullptr;
  if (GetAddrInfoW(host.c_str(), nullptr, &hints, &result) != 0 ||
      result == nullptr) {
    throw std::runtime_error("插件目标域名解析失败");
  }
  bool public_address = false;
  for (ADDRINFOW* current = result; current != nullptr;
       current = current->ai_next) {
    if (IsPrivateAddress(current->ai_addr)) {
      FreeAddrInfoW(result);
      throw std::runtime_error("禁止访问本机或内网地址");
    }
    public_address = true;
  }
  FreeAddrInfoW(result);
  if (!public_address) throw std::runtime_error("插件目标没有公开地址");
}

struct ParsedUrl {
  std::wstring scheme;
  std::wstring host;
  std::wstring path;
  INTERNET_PORT port = 0;
  bool secure = false;
};

ParsedUrl ParseUrl(const std::string& raw) {
  const std::wstring url = Utf8ToWide(raw);
  URL_COMPONENTS parts{};
  parts.dwStructSize = sizeof(parts);
  parts.dwSchemeLength = static_cast<DWORD>(-1);
  parts.dwHostNameLength = static_cast<DWORD>(-1);
  parts.dwUrlPathLength = static_cast<DWORD>(-1);
  parts.dwExtraInfoLength = static_cast<DWORD>(-1);
  if (!WinHttpCrackUrl(url.c_str(), static_cast<DWORD>(url.size()), 0, &parts)) {
    throw std::runtime_error("插件请求 URL 无效");
  }
  ParsedUrl parsed;
  parsed.scheme.assign(parts.lpszScheme, parts.dwSchemeLength);
  parsed.host.assign(parts.lpszHostName, parts.dwHostNameLength);
  parsed.path.assign(parts.lpszUrlPath, parts.dwUrlPathLength);
  if (parts.dwExtraInfoLength > 0) {
    parsed.path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
  }
  parsed.port = parts.nPort;
  parsed.secure = _wcsicmp(parsed.scheme.c_str(), L"https") == 0;
  if (!parsed.secure && _wcsicmp(parsed.scheme.c_str(), L"http") != 0) {
    throw std::runtime_error("插件只能请求 HTTP(S) URL");
  }
  ValidatePublicHost(parsed.host);
  return parsed;
}

std::wstring HeadersFromJs(JSContext* ctx, JSValueConst options,
                           const std::wstring& target_host) {
  JSValue headers = JS_GetPropertyStr(ctx, options, "headers");
  if (!JS_IsObject(headers)) {
    JS_FreeValue(ctx, headers);
    return {};
  }
  JSValue json = JS_JSONStringify(ctx, headers, JS_UNDEFINED, JS_UNDEFINED);
  JS_FreeValue(ctx, headers);
  if (JS_IsException(json)) return {};
  // 由 JS 侧把对象变成 CRLF，避免在 C++ 再实现一套 JSON 解析。
  JSValue global = JS_GetGlobalObject(ctx);
  JS_SetPropertyStr(ctx, global, "__JY_HEADER_JSON__", JS_DupValue(ctx, json));
  const std::string target_host_utf8 = WideToUtf8(target_host);
  JS_SetPropertyStr(ctx, global, "__JY_TARGET_HOST__",
                    JS_NewStringLen(ctx, target_host_utf8.data(),
                                    target_host_utf8.size()));
  JS_FreeValue(ctx, global);
  JS_FreeValue(ctx, json);
  const char* header_script =
      "Object.entries(JSON.parse(globalThis.__JY_HEADER_JSON__))"
      ".filter(([k,v])=>{const base=h=>String(h).toLowerCase().split('.').slice(-2).join('.');"
      "return !/[\\r\\n]/.test(k+v)&&!/^(content-length|connection)$/i.test(k)&&"
      "(!/^host$/i.test(k)||base(v)===base(globalThis.__JY_TARGET_HOST__))})"
      ".map(([k,v])=>`${k}: ${v}`).join('\\r\\n')";
  JSValue lines = JS_Eval(ctx, header_script, strlen(header_script),
                          "<headers>", JS_EVAL_TYPE_GLOBAL);
  if (JS_IsException(lines)) return {};
  std::wstring output = Utf8ToWide(JsString(ctx, lines));
  JS_FreeValue(ctx, lines);
  return output;
}

std::string HttpRequest(JSContext* ctx, HostState& state,
                        const std::string& raw_url, JSValueConst options,
                        int* status) {
  if (++state.request_count > kMaxRequests) {
    throw std::runtime_error("插件请求次数超过安全上限");
  }
  const ParsedUrl url = ParseUrl(raw_url);
  state.hosts.insert(url.host);
  if (state.hosts.size() > kMaxHosts) {
    throw std::runtime_error("插件访问域名数超过安全上限");
  }
  if (std::chrono::steady_clock::now() >= state.deadline) {
    throw std::runtime_error("插件执行超时");
  }
  if (state.session == nullptr) {
    state.session = WinHttpOpen(L"JuYing-TVBox/1.0",
                                WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
                                WINHTTP_NO_PROXY_NAME,
                                WINHTTP_NO_PROXY_BYPASS, 0);
    if (state.session == nullptr) throw std::runtime_error("HTTP 客户端初始化失败");
    WinHttpSetTimeouts(state.session, 5000, 5000, 7000, 7000);
    DWORD decompression = WINHTTP_DECOMPRESSION_FLAG_GZIP |
                          WINHTTP_DECOMPRESSION_FLAG_DEFLATE;
    WinHttpSetOption(state.session, WINHTTP_OPTION_DECOMPRESSION,
                     &decompression, sizeof(decompression));
  }

  std::wstring method = L"GET";
  if (JS_IsObject(options)) {
    JSValue method_value = JS_GetPropertyStr(ctx, options, "method");
    if (!JS_IsUndefined(method_value) && !JS_IsNull(method_value)) {
      method = Utf8ToWide(JsString(ctx, method_value));
      std::transform(method.begin(), method.end(), method.begin(), towupper);
    }
    JS_FreeValue(ctx, method_value);
  }
  if (method != L"GET" && method != L"POST" && method != L"HEAD") {
    throw std::runtime_error("插件请求方法不受支持");
  }

  HINTERNET connection = WinHttpConnect(state.session, url.host.c_str(),
                                         url.port, 0);
  if (connection == nullptr) throw std::runtime_error("连接插件目标失败");
  const DWORD flags = url.secure ? WINHTTP_FLAG_SECURE : 0;
  HINTERNET request = WinHttpOpenRequest(
      connection, method.c_str(), url.path.empty() ? L"/" : url.path.c_str(),
      nullptr, WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES, flags);
  if (request == nullptr) {
    WinHttpCloseHandle(connection);
    throw std::runtime_error("创建插件 HTTP 请求失败");
  }
  DWORD redirect_policy = WINHTTP_OPTION_REDIRECT_POLICY_NEVER;
  WinHttpSetOption(request, WINHTTP_OPTION_REDIRECT_POLICY, &redirect_policy,
                   sizeof(redirect_policy));

  std::string body;
  std::wstring headers;
  if (JS_IsObject(options)) {
    headers = HeadersFromJs(ctx, options, url.host);
    JSValue body_value = JS_GetPropertyStr(ctx, options, "body");
    if (!JS_IsUndefined(body_value) && !JS_IsNull(body_value)) {
      body = JsString(ctx, body_value);
    } else {
      JSValue data_value = JS_GetPropertyStr(ctx, options, "data");
      if (!JS_IsUndefined(data_value) && !JS_IsNull(data_value)) {
        body = Stringify(ctx, data_value);
        if (headers.empty()) headers = L"Content-Type: application/json";
      }
      JS_FreeValue(ctx, data_value);
    }
    JS_FreeValue(ctx, body_value);
  }

  const BOOL sent = WinHttpSendRequest(
      request, headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.c_str(),
      headers.empty() ? 0 : static_cast<DWORD>(-1),
      body.empty() ? WINHTTP_NO_REQUEST_DATA : body.data(),
      static_cast<DWORD>(body.size()), static_cast<DWORD>(body.size()), 0);
  if (!sent || !WinHttpReceiveResponse(request, nullptr)) {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connection);
    throw std::runtime_error("插件 HTTP 请求失败");
  }
  DWORD status_code = 0;
  DWORD status_size = sizeof(status_code);
  WinHttpQueryHeaders(request,
                      WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                      WINHTTP_HEADER_NAME_BY_INDEX, &status_code, &status_size,
                      WINHTTP_NO_HEADER_INDEX);
  *status = static_cast<int>(status_code);

  if (status_code >= 300 && status_code < 400) {
    DWORD location_size = 0;
    WinHttpQueryHeaders(request, WINHTTP_QUERY_LOCATION,
                        WINHTTP_HEADER_NAME_BY_INDEX, nullptr, &location_size,
                        WINHTTP_NO_HEADER_INDEX);
    if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && location_size > 0 &&
        location_size < 16 * 1024) {
      std::wstring location(location_size / sizeof(wchar_t), L'\0');
      if (WinHttpQueryHeaders(request, WINHTTP_QUERY_LOCATION,
                              WINHTTP_HEADER_NAME_BY_INDEX, location.data(),
                              &location_size, WINHTTP_NO_HEADER_INDEX)) {
        location.resize(wcsnlen(location.c_str(), location.size()));
        const std::wstring base = Utf8ToWide(raw_url);
        DWORD combined_size = 8192;
        std::wstring combined(combined_size, L'\0');
        if (UrlCombineW(base.c_str(), location.c_str(), combined.data(),
                        &combined_size, URL_ESCAPE_UNSAFE) == S_OK) {
          combined.resize(combined_size);
          const std::string redirected = WideToUtf8(combined);
          // 在发起下一跳前重新执行 DNS 与内网地址校验。
          ParseUrl(redirected);
          WinHttpCloseHandle(request);
          WinHttpCloseHandle(connection);
          return HttpRequest(ctx, state, redirected, options, status);
        }
      }
    }
  }

  std::string output;
  while (true) {
    DWORD available = 0;
    if (!WinHttpQueryDataAvailable(request, &available)) break;
    if (available == 0) break;
    if (output.size() + available > kMaxResponseBytes) {
      WinHttpCloseHandle(request);
      WinHttpCloseHandle(connection);
      throw std::runtime_error("插件 HTTP 响应超过安全上限");
    }
    const size_t offset = output.size();
    output.resize(offset + available);
    DWORD read = 0;
    if (!WinHttpReadData(request, output.data() + offset, available, &read)) {
      output.resize(offset);
      break;
    }
    output.resize(offset + read);
  }
  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connection);
  return output;
}

JSValue JsHttp(JSContext* ctx, JSValueConst, int argc, JSValueConst* argv) {
  auto* state = static_cast<HostState*>(JS_GetRuntimeOpaque(JS_GetRuntime(ctx)));
  try {
    if (argc < 1) return JS_ThrowTypeError(ctx, "HTTP URL is required");
    const std::string url = JsString(ctx, argv[0]);
    const JSValueConst options = argc > 1 ? argv[1] : JS_UNDEFINED;
    int status = 0;
    const std::string content = HttpRequest(ctx, *state, url, options, &status);
    JSValue result = JS_NewObject(ctx);
    JS_SetPropertyStr(ctx, result, "code", JS_NewInt32(ctx, status));
    JS_SetPropertyStr(ctx, result, "content",
                      JS_NewStringLen(ctx, content.data(), content.size()));
    JS_SetPropertyStr(ctx, result, "headers", JS_NewObject(ctx));
    return result;
  } catch (const std::exception& error) {
    state->error = error.what();
    return JS_ThrowInternalError(ctx, "%s", error.what());
  }
}

int InterruptHandler(JSRuntime* runtime, void*) {
  auto* state = static_cast<HostState*>(JS_GetRuntimeOpaque(runtime));
  return std::chrono::steady_clock::now() >= state->deadline ? 1 : 0;
}

char* ModuleNormalize(JSContext* ctx, const char* base_name,
                      const char* name, void*) {
  try {
    std::string module(name);
    if (module.rfind("http://", 0) != 0 && module.rfind("https://", 0) != 0) {
      const std::wstring base = Utf8ToWide(base_name == nullptr ? "" : base_name);
      const std::wstring child = Utf8ToWide(module);
      DWORD length = 4096;
      std::wstring combined(length, L'\0');
      if (UrlCombineW(base.c_str(), child.c_str(), combined.data(), &length,
                      URL_ESCAPE_UNSAFE) != S_OK) {
        return nullptr;
      }
      combined.resize(length);
      module = WideToUtf8(combined);
    }
    char* result = static_cast<char*>(js_malloc(ctx, module.size() + 1));
    if (result == nullptr) return nullptr;
    memcpy(result, module.c_str(), module.size() + 1);
    return result;
  } catch (...) {
    return nullptr;
  }
}

JSModuleDef* ModuleLoader(JSContext* ctx, const char* module_name, void*) {
  auto* state = static_cast<HostState*>(JS_GetRuntimeOpaque(JS_GetRuntime(ctx)));
  try {
    int status = 0;
    JSValue empty_options = JS_NewObject(ctx);
    const std::string source =
        HttpRequest(ctx, *state, module_name, empty_options, &status);
    JS_FreeValue(ctx, empty_options);
    if (status < 200 || status >= 300) {
      JS_ThrowReferenceError(ctx, "模块请求失败（HTTP %d）：%s", status,
                             module_name);
      return nullptr;
    }
    JSValue compiled = JS_Eval(ctx, source.data(), source.size(), module_name,
                               JS_EVAL_TYPE_MODULE | JS_EVAL_FLAG_COMPILE_ONLY);
    if (JS_IsException(compiled)) return nullptr;
    JSModuleDef* module = static_cast<JSModuleDef*>(JS_VALUE_GET_PTR(compiled));
    JS_FreeValue(ctx, compiled);
    return module;
  } catch (const std::exception& error) {
    state->error = error.what();
    JS_ThrowReferenceError(ctx, "%s", error.what());
    return nullptr;
  }
}

std::string ExceptionText(JSContext* ctx) {
  JSValue exception = JS_GetException(ctx);
  std::string result;
  try {
    result = JsString(ctx, exception);
    JSValue stack = JS_GetPropertyStr(ctx, exception, "stack");
    if (!JS_IsUndefined(stack)) result += "\n" + JsString(ctx, stack);
    JS_FreeValue(ctx, stack);
  } catch (...) {
    result = "JavaScript 执行失败";
  }
  JS_FreeValue(ctx, exception);
  return result;
}

void EvalOrThrow(JSContext* ctx, const std::string& code,
                 const char* filename, int flags = JS_EVAL_TYPE_GLOBAL) {
  JSValue result;
  if ((flags & JS_EVAL_TYPE_MASK) == JS_EVAL_TYPE_MODULE) {
    result = JS_Eval(ctx, code.data(), code.size(), filename,
                     flags | JS_EVAL_FLAG_COMPILE_ONLY);
    if (!JS_IsException(result)) result = JS_EvalFunction(ctx, result);
    while (!JS_IsException(result) && JS_IsPromise(result) &&
           JS_PromiseState(ctx, result) == JS_PROMISE_PENDING) {
      JSContext* job_context = nullptr;
      const int jobs = JS_ExecutePendingJob(JS_GetRuntime(ctx), &job_context);
      if (jobs < 0) {
        JS_FreeValue(ctx, result);
        throw std::runtime_error(ExceptionText(job_context));
      }
      if (jobs == 0) break;
    }
    if (!JS_IsException(result) && JS_IsPromise(result) &&
        JS_PromiseState(ctx, result) == JS_PROMISE_REJECTED) {
      JSValue reason = JS_PromiseResult(ctx, result);
      std::string message = JsString(ctx, reason);
      JSValue stack = JS_GetPropertyStr(ctx, reason, "stack");
      if (!JS_IsUndefined(stack)) message += "\n" + JsString(ctx, stack);
      JS_FreeValue(ctx, stack);
      JS_FreeValue(ctx, reason);
      JS_FreeValue(ctx, result);
      throw std::runtime_error(message);
    }
  } else {
    result = JS_Eval(ctx, code.data(), code.size(), filename, flags);
  }
  if (JS_IsException(result)) {
    throw std::runtime_error(ExceptionText(ctx));
  }
  JS_FreeValue(ctx, result);
}

}  // namespace

int main() {
  SetConsoleOutputCP(CP_UTF8);
  WSADATA winsock{};
  if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0) {
    std::cerr << "网络运行时初始化失败";
    return 2;
  }
  std::string input((std::istreambuf_iterator<char>(std::cin)),
                    std::istreambuf_iterator<char>());
  HostState state{std::chrono::steady_clock::now() + kDeadline};
  JSRuntime* runtime = JS_NewRuntime();
  JSContext* context = runtime == nullptr ? nullptr : JS_NewContext(runtime);
  if (runtime == nullptr || context == nullptr) {
    std::cerr << "QuickJS 初始化失败";
    if (context != nullptr) JS_FreeContext(context);
    if (runtime != nullptr) JS_FreeRuntime(runtime);
    WSACleanup();
    return 2;
  }
  JS_SetRuntimeOpaque(runtime, &state);
  JS_SetMemoryLimit(runtime, kMemoryLimit);
  JS_SetMaxStackSize(runtime, kStackLimit);
  JS_SetInterruptHandler(runtime, InterruptHandler, nullptr);
  JS_SetModuleLoaderFunc(runtime, ModuleNormalize, ModuleLoader, nullptr);

  int exit_code = 0;
  try {
    JSValue request = JS_ParseJSON(context, input.data(), input.size(), "<rpc>");
    if (JS_IsException(request) || !JS_IsObject(request)) {
      if (!JS_IsException(request)) JS_FreeValue(context, request);
      throw std::runtime_error("插件 RPC 请求格式无效");
    }
    const std::string api = PropertyString(context, request, "api");
    const std::string ext = PropertyString(context, request, "ext");
    const std::string method = PropertyString(context, request, "method");
    if (method != "home" && method != "homeVod" && method != "category" &&
        method != "detail" && method != "search" && method != "play") {
      JS_FreeValue(context, request);
      throw std::runtime_error("插件 RPC 方法不在允许列表");
    }
    ParseUrl(api);
    JSValue args = JS_GetPropertyStr(context, request, "args");
    const std::string arguments = Stringify(context, args);
    JS_FreeValue(context, args);
    JS_FreeValue(context, request);

    JSValue global = JS_GetGlobalObject(context);
    JS_SetPropertyStr(context, global, "__juyingHttp",
                      JS_NewCFunction(context, JsHttp, "__juyingHttp", 2));
    JS_FreeValue(context, global);
    EvalOrThrow(context, R"JS(
globalThis.req = globalThis.__juyingHttp;
globalThis._http = globalThis.__juyingHttp;
globalThis.local = {get(){return ''}, set(){}, delete(){}};
globalThis.console = {log(){}, error(){}, warn(){}, info(){}};
globalThis.joinUrl = (base, child) => {
  if (/^https?:\/\//i.test(child)) return child;
  const match = String(base).match(/^(https?:\/\/[^/]+)(\/.*)?$/i);
  if (!match) return child;
  if (String(child).startsWith('/')) return match[1] + child;
  const path = (match[2] || '/').replace(/[^/]*$/, '');
  return match[1] + path + child;
};
globalThis.getProxy = () => '';
globalThis.print = globalThis.log = (...args) => console.log(...args);
globalThis.pdfh = () => '';
globalThis.pdfa = () => [];
globalThis.pd = () => '';
globalThis.pdfl = () => [];
for (const name of ['window', 'self', 'global']) {
  Object.defineProperty(globalThis, name, {get(){return globalThis}});
}
)JS", "<juying-bootstrap>");

    std::string entry =
        "import __plugin from " + JsonQuote(api) + ";\n" +
        "const __spider=typeof __plugin==='function'?__plugin():__plugin;\n" +
        "__spider.init(" + JsonQuote(ext) + ");\n" +
        "globalThis.__JY_RESULT__=__spider[" + JsonQuote(method) +
        "](..." + arguments + ");globalThis.__JY_DONE__=true;";
    EvalOrThrow(context, entry, "https://juying.invalid/entry.mjs",
                JS_EVAL_TYPE_MODULE);

    while (true) {
      JSValue global_object = JS_GetGlobalObject(context);
      JSValue done_value = JS_GetPropertyStr(context, global_object, "__JY_DONE__");
      const bool done = JS_ToBool(context, done_value) == 1;
      JS_FreeValue(context, done_value);
      JS_FreeValue(context, global_object);
      if (done) break;
      JSContext* job_context = nullptr;
      const int jobs = JS_ExecutePendingJob(runtime, &job_context);
      if (jobs < 0) throw std::runtime_error(ExceptionText(job_context));
      if (jobs == 0) throw std::runtime_error("插件模块未完成初始化");
      if (std::chrono::steady_clock::now() >= state.deadline) {
        throw std::runtime_error("插件执行超时");
      }
    }
    JSValue global_object = JS_GetGlobalObject(context);
    JSValue result = JS_GetPropertyStr(context, global_object, "__JY_RESULT__");
    const std::string result_json = Stringify(context, result);
    JS_FreeValue(context, result);
    JS_FreeValue(context, global_object);
    std::cout << "{\"ok\":true,\"result\":" << result_json << '}';
  } catch (const std::exception& error) {
    std::cout << "{\"ok\":false,\"error\":" << JsonQuote(error.what()) << '}';
  } catch (...) {
    std::cout << "{\"ok\":false,\"error\":\"插件宿主发生未知错误\"}";
  }

  JS_FreeContext(context);
  JS_FreeRuntime(runtime);
  WSACleanup();
  return exit_code;
}
