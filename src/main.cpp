#include"server.h"
#include<Windows.h>
#include<detours/detours.h>
#include <include/internal/cef_types_win.h>
#include<include/capi/cef_client_capi.h>
#include"utils.h"
#include "console.h"
#include<iostream>
#include<print>
#include"logger.h"

ServerWrapper server;

typedef int(CEF_EXPORT* cef_string_from_ptr_t)(const TCHAR*, size_t, cef_string_utf16_t*);
cef_string_from_ptr_t cef_string_from_ptr = nullptr;
#ifdef UNICODE
typedef std::wstring _string;
#define convertStr to_wide_string
#else
typedef std::string _string;
#define convertStr to_byte_string
#endif
cef_string_t toCefString(_string s) {
	cef_string_t cs{};
	cef_string_from_ptr(s.c_str(), s.length(), &cs);
	return cs;
}
void SetAsPopup(cef_window_info_t* window_info) {
	window_info->style =
		WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN | WS_CLIPSIBLINGS | WS_VISIBLE;
	window_info->parent_window = NULL;
	window_info->x = CW_USEDEFAULT;
	window_info->y = CW_USEDEFAULT;
	window_info->width = CW_USEDEFAULT;
	window_info->height = CW_USEDEFAULT;
}

void evalJS(_cef_browser_t* browser, _cef_frame_t* frame, std::string code) {
	_string eval_str = convertStr(code);
	cef_string_t eval{};
	cef_string_from_ptr(eval_str.c_str(), eval_str.length(), &eval);
	cef_string_t url{};
	auto u = frame->get_url(frame);
	_string url_str = TEXT("http://localhost:8080/static/index.js");
	cef_string_from_ptr(url_str.c_str(), url_str.length(), &url);
	frame->execute_java_script(frame, &eval, &url, 0);
}

namespace handlers {
	namespace origins {
		PVOID pOnLoadStart = nullptr;
		PVOID pOnKeyEvent = nullptr;
	};
	void CEF_CALLBACK onLoadStart(struct _cef_load_handler_t* self,
		_cef_browser_t* browser,
		_cef_frame_t* frame,
		cef_transition_type_t transition_type) {
		Logger::info("is_main_frame:{}",frame->is_main(frame));
		if (frame->is_main(frame)) {
			Logger::info("主页面开始加载，注入预加载脚本");
			evalJS(browser, frame, "window._etb_resserver='http://localhost:8080/static';");
			evalJS(browser, frame, "window._ets_cache_path='http://localhost:8080/ets';");
			evalJS(browser, frame, "window._etb_api='http://localhost:8080/api';");
			std::ifstream f(STATIC_FILES_PATH + "/index.js");
			if (f.is_open()) {
				std::string str((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
				f.close();
				evalJS(browser, frame, str);
			}else Logger::error("index.js文件不存在，请考虑删除{}文件夹并重启E听说", STATIC_FILES_PATH);
		}
		else {
			Logger::info("iframe开始加载，注入预加载脚本");
			std::ifstream f(STATIC_FILES_PATH + "/index.iframe.js");
			if (f.is_open()) {
				std::string str((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
				f.close();
				evalJS(browser, frame, str);
			}
			else Logger::error("index.iframe.js文件不存在，请考虑删除{}文件夹并重启E听说", STATIC_FILES_PATH);
		}

		return reinterpret_cast<decltype(&handlers::onLoadStart)>(origins::pOnLoadStart)(self, browser, frame, transition_type);
	};
	int CEF_CALLBACK onKeyEvent(struct _cef_keyboard_handler_t* self,
		struct _cef_browser_t* browser,
		const struct _cef_key_event_t* event,
		cef_event_handle_t os_event) {
		auto host = browser->get_host(browser);
		if (event->type == KEYEVENT_RAWKEYDOWN) {
			if (event->windows_key_code == VK_F12) {
				cef_window_info_t windowInfo{};
				cef_browser_settings_t settings{};
				cef_point_t point{};
				SetAsPopup(&windowInfo);
				host->show_dev_tools(host, &windowInfo, 0, &settings, &point);
			}
		}
		return reinterpret_cast<decltype(&handlers::onKeyEvent)>(origins::pOnKeyEvent)(self, browser, event, os_event);
	};
};

PVOID pGetKeyboardHandler = nullptr;
_cef_keyboard_handler_t* CEF_CALLBACK hGetKeyboardHandler(_cef_client_t* self) {
	auto handler = reinterpret_cast<decltype(&hGetKeyboardHandler)>(pGetKeyboardHandler)(self);
	handlers::origins::pOnKeyEvent = handler->on_key_event;
	handler->on_key_event = handlers::onKeyEvent;
	return handler;
}
PVOID pGetLoadHandler = nullptr;
_cef_load_handler_t* CEF_CALLBACK hGetLoadHandler(_cef_client_t* self) {
	auto handler = reinterpret_cast<decltype(&hGetLoadHandler)>(pGetLoadHandler)(self);
	handlers::origins::pOnLoadStart = handler->on_load_start;
	handler->on_load_start = handlers::onLoadStart;
	return handler;
}

PVOID pCefBrowserHostCreateBrowser = nullptr;
int h_cef_browser_host_create_browser(
	const cef_window_info_t* windowInfo,
	struct _cef_client_t* client,
	const cef_string_t* url,
	const struct _cef_browser_settings_t* settings,
	struct _cef_dictionary_value_t* extra_info,
	struct _cef_request_context_t* request_context)
{
	Logger::info("[Hook] 浏览器窗口创建");
	pGetKeyboardHandler = client->get_keyboard_handler;
	client->get_keyboard_handler = hGetKeyboardHandler;
	pGetLoadHandler = client->get_load_handler;
	client->get_load_handler = hGetLoadHandler;
	return reinterpret_cast<decltype(&h_cef_browser_host_create_browser)>(pCefBrowserHostCreateBrowser)(windowInfo, client, url, settings, extra_info, request_context);
}

PVOID pCefShutdown = nullptr;
void hCefShutdown() {
	server.shutdown();
	return reinterpret_cast<decltype(&hCefShutdown)>(pCefShutdown)();
}
void setupHooks() {
	Logger::info("初始化Hook中");
	DetourTransactionBegin();
	DetourUpdateThread(GetCurrentThread());
	pCefBrowserHostCreateBrowser = DetourFindFunction("libcef.dll", "cef_browser_host_create_browser");
#ifdef UNICODE
	cef_string_from_ptr = reinterpret_cast<cef_string_from_ptr_t>(DetourFindFunction("libcef.dll", "cef_string_wide_to_utf16"));
#else
	cef_string_from_ptr = reinterpret_cast<cef_string_from_ptr_t>(DetourFindFunction("libcef.dll", "cef_string_ascii_to_utf16"));
#endif
	DetourAttach(&pCefBrowserHostCreateBrowser, (PVOID)h_cef_browser_host_create_browser);
	auto result = DetourTransactionCommit();
	Logger::info("为libcef.dll/cef_browser_host_create_browser({})附加Hook 状态：{}", pCefBrowserHostCreateBrowser, result == NO_ERROR ? "成功" : "失败");
	DetourTransactionBegin();
	pCefShutdown = DetourFindFunction("libcef.dll", "cef_shutdown");
	DetourAttach(&pCefShutdown, (PVOID)hCefShutdown);
	result = DetourTransactionCommit();
	Logger::info("为libcef.dll/cef_shutdown({})附加Hook 状态：{}", pCefShutdown, result == NO_ERROR ? "成功" : "失败");
}

DWORD WINAPI ThreadProc(LPVOID lpThreadParameter)
{
	HANDLE hProcess;

	PVOID addr1 = reinterpret_cast<PVOID>(0x00401000);
	BYTE data1[] = { 0x90, 0x90, 0x90, 0x90 };

	//
	// 绕过VMP3.x 的内存保护
	//
	hProcess = OpenProcess(PROCESS_VM_OPERATION | PROCESS_VM_READ | PROCESS_VM_WRITE, FALSE, GetCurrentProcessId());
	if (hProcess)
	{
		WriteProcessMemory(hProcess, addr1, data1, sizeof(data1), NULL);
		CloseHandle(hProcess);
	}
	bool isMainProc = isMainProcess();
	if (isMainProc)
		createConsole();
	Logger::info("进程参数：{} 主进程：{}", GetCommandLineA(), isMainProc);
	setupHooks();
	server.listen();
	Logger::info("加载完成。按下F12可打开js控制台。");
	return 0;
}