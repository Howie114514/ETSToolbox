#include"utils.h"
#include<Windows.h>

extern "C" IMAGE_DOS_HEADER __ImageBase;

std::wstring to_wide_string(const std::string& input) {
	std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
	return converter.from_bytes(input);
}

std::string to_byte_string(const std::wstring& input) {
	std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
	return converter.to_bytes(input);
}

std::filesystem::path getModuleDirectory()
{
	std::wstring modulePath(32768, L'\0');
	const auto module = reinterpret_cast<HMODULE>(&__ImageBase);
	const DWORD length = GetModuleFileNameW(module, modulePath.data(), static_cast<DWORD>(modulePath.size()));
	if (length == 0 || length >= modulePath.size()) {
		return std::filesystem::current_path();
	}
	modulePath.resize(length);
	return std::filesystem::path(modulePath).parent_path();
}

std::filesystem::path getStaticFilesDirectory()
{
	return getModuleDirectory() / L"etstoolbox";
}

bool isMainProcess()
{
	int argCount;
	LPWSTR* cl = CommandLineToArgvW(GetCommandLine(), &argCount);
	return argCount <= 2;
}

std::string fileToDataURL(std::string path, std::string type = "text/javascript") {
	std::ifstream file(path);
	std::string str((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
	file.close();
	return "data:" + type + ";base64," + base64_encode(str);
}
