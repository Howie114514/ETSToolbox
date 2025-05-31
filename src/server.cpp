#include<httplib.h>
#include<filesystem>
#include<cstdio>
#include"server.h"
#include"logger.h"
#include<fstream>

ServerWrapper::ServerWrapper()
{
	this->server.set_mount_point("/static", STATIC_FILES_PATH);
	this->server.set_mount_point("/ets", (std::filesystem::path(getenv("appdata")) / "ETS").string());
	this->server.Get("/api/read_config", [&](const httplib::Request& req, httplib::Response& res) {
		std::ifstream file(STATIC_FILES_PATH + "/settings.json");
		if (file.is_open()) {
			std::string str((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
			res.set_content(str,"application/json");
		}
		else {
			res.set_content("error","text/plain");
		}
		
	});
	this->server.Post("/api/write_config", [&](const httplib::Request& req, httplib::Response& res) {
		std::ofstream file(STATIC_FILES_PATH + "/settings.json");
		if (file.is_open()) {
			file << req.body;
			file.close();
		}
		else {
			res.set_content("error", "text/plain");
			file.close();
		}
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
	Logger::info("服务器开启于端口8080");
	std::thread t = std::thread([this]() {
		this->server.listen("127.0.0.1", 8080);
		});
	t.detach();
}