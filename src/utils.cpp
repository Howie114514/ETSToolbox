#include"utils.h"

std::wstring to_wide_string(const std::string& input) {
	std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
	return converter.from_bytes(input);
}

std::string to_byte_string(const std::wstring& input) {
	std::wstring_convert<std::codecvt_utf8<wchar_t>> converter;
	return converter.to_bytes(input);
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