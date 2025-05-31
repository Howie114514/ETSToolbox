#include "console.h"
#include<cstdio>

void createConsole()
{
	if (AllocConsole()) {
		SetConsoleTitle(L"Eฬýหตอโนา");
		freopen("conout$", "w", stdout);
		freopen("conout$", "w", stderr);
	}
}