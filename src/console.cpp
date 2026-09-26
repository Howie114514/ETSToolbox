#include "console.h"
#include<cstdio>

void createConsole()
{
	if (AllocConsole()) {
		SetConsoleCP(CP_UTF8);
		SetConsoleOutputCP(CP_UTF8);
		SetConsoleTitle(L"ETSToolbox");
		freopen("conout$", "w", stdout);
		freopen("conout$", "w", stderr);
	}
}
