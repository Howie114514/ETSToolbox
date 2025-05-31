#pragma once
#include<httplib.h>
#include<thread>

#ifdef DEBUG_MODE
#define STATIC_FILES_PATH (std::filesystem::path(getenv("userprofile"))/"etstoolbox").string()
#else
#define STATIC_FILES_PATH (std::filesystem::absolute(".")/"etstoolbox").string()
#endif

class ServerWrapper {
private:
	httplib::Server server;
public:
	ServerWrapper();
	void listen();
	void shutdown();
};