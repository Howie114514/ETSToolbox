#pragma once
#include<format>
#include<iostream>
#include<print>
#include<string>
#include<chrono>
#include<map>
#include <unordered_map>

namespace {
	namespace Logger {
		std::string getTimestamp() {
			auto now = std::chrono::system_clock::now();
			return std::format("{:%Y-%m-%d %H:%M:%S}", now);
		}
		enum Levels {
			I = 1,
			E = 3,
			D = 0,
			W = 2
		};
		std::unordered_map<Levels, WORD> colors = {
			{Levels::I,FOREGROUND_BLUE},
			{Levels::D,FOREGROUND_RED | FOREGROUND_BLUE},
			{Levels::E,FOREGROUND_RED},
			{Levels::W,FOREGROUND_RED | FOREGROUND_GREEN}
		};
		std::unordered_map<Levels, std::string> names = {
			{Levels::I ,"INFO",},
			{Levels::E,"ERROR"},
			{Levels::D,"DEBUG"},
			{Levels::W,"WARN"}
		};
		void outputLevel(Levels lvl) {
			auto hConsole = GetStdHandle(STD_OUTPUT_HANDLE);
			SetConsoleTextAttribute(hConsole, colors[lvl]);
			std::cout << names[lvl];
			SetConsoleTextAttribute(hConsole, 7);
		}
		template<typename... Args>
		void _log(Levels lvl, std::format_string<Args...> fmt, Args ...args);
		template<typename... Args>
		void _log(Levels lvl, std::format_string<Args...> fmt, Args ...args) {
			std::print("[EÌýËµÍâ¹Ò] {} [", getTimestamp());
			outputLevel(lvl);
			std::println("] - {}", std::format(fmt, std::forward<Args>(args)...));
		};
		template<typename... Args>
		void info(std::format_string<Args...> fmt, Args ...args);
		template<typename... Args>
		void info(std::format_string<Args...> fmt, Args ...args) {
			_log(Levels::I, fmt, std::forward<Args>(args)...);
		}
		template<typename... Args>
		void error(std::format_string<Args...> fmt, Args ...args);
		template<typename... Args>
		void error(std::format_string<Args...> fmt, Args ...args) {
			_log(Levels::E, fmt, std::forward<Args>(args)...);
		}
		template<typename... Args>
		void debug(std::format_string<Args...> fmt, Args ...args);
		template<typename... Args>
		void debug(std::format_string<Args...> fmt, Args ...args) {
			_log(Levels::D, fmt, std::forward<Args>(args)...);
		}
		template<typename... Args>
		void warn(std::format_string<Args...> fmt, Args ...args);
		template<typename... Args>
		void warn(std::format_string<Args...> fmt, Args ...args) {
			_log(Levels::W, fmt, std::forward<Args>(args)...);
		}
	}
};