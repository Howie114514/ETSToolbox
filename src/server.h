#pragma once
#include<httplib.h>
#include<thread>
#include"utils.h"

class ServerWrapper {
private:
	httplib::Server server;
public:
	ServerWrapper();
	void listen();
	void shutdown();
};
