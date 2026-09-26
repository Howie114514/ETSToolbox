#pragma once
#include<fstream>
#include<filesystem>
#include <string>
#include <locale>
#include <codecvt>
#include"./base64.h"
#include <include/capi/cef_browser_capi.h>
std::wstring to_wide_string(const std::string& input);
std::string to_byte_string(const std::wstring& input);
std::filesystem::path getModuleDirectory();
std::filesystem::path getStaticFilesDirectory();
std::string fileToDataURL(std::string path);
void evalJS(_cef_browser_t* browser, _cef_frame_t* frame, std::string code);
bool isMainProcess();
