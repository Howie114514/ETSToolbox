#include<httplib.h>
#include<algorithm>
#include<cstdint>
#include<filesystem>
#include<cstdio>
#include<Windows.h>
#include"server.h"
#include"utils.h"
#include"logger.h"
#include<fstream>
#include<format>
#include<optional>
#include<sstream>
#include<string>
#include<unordered_set>
#include<utility>
#include<vector>

namespace {
	constexpr std::uintmax_t maxMetadataFileSize = 16 * 1024 * 1024;
	constexpr std::size_t maxLookupBodySize = 64 * 1024;

	std::vector<std::string> parseLookupTerms(const std::string& body)
	{
		std::vector<std::string> terms;
		std::unordered_set<std::string> seen;
		std::istringstream input(body);
		std::string line;
		while (terms.size() < 32 && std::getline(input, line)) {
			if (!line.empty() && line.back() == '\r') line.pop_back();
			const auto first = line.find_first_not_of(" \t");
			const auto last = line.find_last_not_of(" \t");
			if (first == std::string::npos || last == std::string::npos) continue;
			line = line.substr(first, last - first + 1);
			if (line.size() < 6 || line.size() > 512 || !seen.insert(line).second) continue;
			terms.push_back(std::move(line));
		}
		return terms;
	}

	bool isContentMetadataFile(const std::filesystem::path& path)
	{
		const auto name = path.filename().wstring();
		if (name != L"content.json" && name != L"content2.json") return false;
		for (const auto& part : path.parent_path()) {
			const auto value = part.wstring();
			if (value.rfind(L"content_", 0) == 0) return true;
		}
		return false;
	}

	std::optional<std::pair<std::filesystem::path, std::string>> findLocalAnswerMetadata(
		const std::filesystem::path& etsRoot,
		const std::vector<std::string>& terms)
	{
		std::filesystem::path bestPath;
		std::string bestContent;
		std::size_t bestMatches = 0;
		std::size_t bestLongestMatch = 0;
		int bestFilePriority = -1;
		std::error_code error;
		std::filesystem::recursive_directory_iterator iterator(
			etsRoot,
			std::filesystem::directory_options::skip_permission_denied,
			error
		);
		const std::filesystem::recursive_directory_iterator end;

		while (!error && iterator != end) {
			const auto entry = *iterator;
			iterator.increment(error);
			if (error) {
				error.clear();
				continue;
			}
			if (!entry.is_regular_file(error) || error || !isContentMetadataFile(entry.path())) {
				error.clear();
				continue;
			}
			const auto size = entry.file_size(error);
			if (error || size == 0 || size > maxMetadataFileSize) {
				error.clear();
				continue;
			}

			std::ifstream file(entry.path(), std::ios::binary);
			if (!file.is_open()) continue;
			std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
			std::size_t matches = 0;
			std::size_t longestMatch = 0;
			for (const auto& term : terms) {
				if (content.find(term) == std::string::npos) continue;
				matches++;
				longestMatch = (std::max)(longestMatch, term.size());
			}
			const int filePriority = entry.path().filename() == L"content2.json" ? 1 : 0;
			if (matches == 0 ||
				matches < bestMatches ||
				(matches == bestMatches && longestMatch < bestLongestMatch) ||
				(matches == bestMatches && longestMatch == bestLongestMatch && filePriority <= bestFilePriority)) {
				continue;
			}

			bestPath = entry.path();
			bestContent = std::move(content);
			bestMatches = matches;
			bestLongestMatch = longestMatch;
			bestFilePriority = filePriority;
		}

		if (bestMatches == 0) return std::nullopt;
		return std::make_pair(std::move(bestPath), std::move(bestContent));
	}

	bool launchAnswerConsole(const std::filesystem::path& scriptPath, DWORD& errorCode)
	{
		std::wstring systemDirectory(MAX_PATH, L'\0');
		const UINT systemDirectoryLength = GetSystemDirectoryW(
			systemDirectory.data(),
			static_cast<UINT>(systemDirectory.size())
		);
		if (systemDirectoryLength == 0 || systemDirectoryLength >= systemDirectory.size()) {
			errorCode = GetLastError();
			return false;
		}
		systemDirectory.resize(systemDirectoryLength);

		const auto powershellPath = std::filesystem::path(systemDirectory) /
			L"WindowsPowerShell" / L"v1.0" / L"powershell.exe";
		if (!std::filesystem::is_regular_file(powershellPath)) {
			errorCode = ERROR_FILE_NOT_FOUND;
			return false;
		}

		std::wstring commandLine = L"\"" + powershellPath.wstring() +
			L"\" -NoLogo -NoProfile -ExecutionPolicy Bypass -File \"" +
			scriptPath.wstring() + L"\"";
		STARTUPINFOW startupInfo{};
		startupInfo.cb = sizeof(startupInfo);
		PROCESS_INFORMATION processInfo{};
		const auto workingDirectory = scriptPath.parent_path().wstring();
		const BOOL created = CreateProcessW(
			powershellPath.c_str(),
			commandLine.data(),
			nullptr,
			nullptr,
			FALSE,
			CREATE_NEW_CONSOLE | CREATE_UNICODE_ENVIRONMENT,
			nullptr,
			workingDirectory.c_str(),
			&startupInfo,
			&processInfo
		);
		if (!created) {
			errorCode = GetLastError();
			return false;
		}

		CloseHandle(processInfo.hThread);
		CloseHandle(processInfo.hProcess);
		errorCode = ERROR_SUCCESS;
		return true;
	}
}

ServerWrapper::ServerWrapper()
{
	const auto staticFilesPath = getStaticFilesDirectory();
	std::filesystem::path etsDataPath;
	this->server.set_mount_point("/static", staticFilesPath.string());
	if (const char* appData = getenv("appdata"); appData != nullptr) {
		etsDataPath = std::filesystem::path(appData) / "ETS";
		this->server.set_mount_point("/ets", etsDataPath.string());
	}
	this->server.Get("/api/read_config", [&](const httplib::Request& req, httplib::Response& res) {
		std::ifstream file(getStaticFilesDirectory() / "settings.json");
		if (file.is_open()) {
			std::string str((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
			res.set_content(str,"application/json");
		}
		else {
			res.set_content("error","text/plain");
		}
		
	});
	this->server.Post("/api/write_config", [&](const httplib::Request& req, httplib::Response& res) {
		std::ofstream file(getStaticFilesDirectory() / "settings.json");
		if (file.is_open()) {
			file << req.body;
			file.close();
			res.set_content("ok", "text/plain; charset=utf-8");
		}
		else {
			res.set_content("error", "text/plain");
			file.close();
		}
	});
	this->server.Post("/api/open_answer_console", [&](const httplib::Request& req, httplib::Response& res) {
		const auto scriptPath = getStaticFilesDirectory() / "answer-console.ps1";
		if (!std::filesystem::is_regular_file(scriptPath)) {
			Logger::error("答案终端启动脚本不存在：{}", to_byte_string(scriptPath.wstring()));
			res.status = 404;
			res.set_content("答案终端启动脚本不存在", "text/plain; charset=utf-8");
			return;
		}

		DWORD errorCode = ERROR_SUCCESS;
		if (!launchAnswerConsole(scriptPath, errorCode)) {
			Logger::error("无法启动答案终端，Win32 错误码：{}", errorCode);
			res.status = 500;
			res.set_content(
				std::format("无法启动系统 PowerShell（Win32 错误码 {}）", errorCode),
				"text/plain; charset=utf-8"
			);
			return;
		}

		Logger::info("已打开答案终端");
		res.set_content("ok", "text/plain; charset=utf-8");
	});
	this->server.Post("/api/find_local_answers", [etsDataPath](const httplib::Request& req, httplib::Response& res) {
		res.set_header("Access-Control-Allow-Origin", "*");
		res.set_header("Cache-Control", "no-store");
		if (req.body.size() > maxLookupBodySize) {
			res.status = 413;
			res.set_content("查询内容过长", "text/plain; charset=utf-8");
			return;
		}
		const auto terms = parseLookupTerms(req.body);
		if (terms.empty()) {
			res.status = 400;
			res.set_content("没有可用的题目特征", "text/plain; charset=utf-8");
			return;
		}
		if (etsDataPath.empty() || !std::filesystem::is_directory(etsDataPath)) {
			res.status = 404;
			res.set_content("本机题库目录不存在", "text/plain; charset=utf-8");
			return;
		}

		const auto match = findLocalAnswerMetadata(etsDataPath, terms);
		if (!match) {
			Logger::info("本机题库未找到当前题目的参考答案元数据");
			res.status = 404;
			res.set_content("未找到匹配的题目元数据", "text/plain; charset=utf-8");
			return;
		}

		Logger::info("已从本机题库匹配答案元数据：{}", to_byte_string(match->first.wstring()));
		res.set_content(match->second, "application/json; charset=utf-8");
	});
}

void ServerWrapper::shutdown()
{
	if (this->server.is_running()) {
		this->server.stop();
	}
}

void ServerWrapper::listen()
{
	Logger::info("服务器开启于端口8080，前端目录：{}", to_byte_string(getStaticFilesDirectory().wstring()));
	std::thread t = std::thread([this]() {
		this->server.listen("127.0.0.1", 8080);
		});
	t.detach();
}
