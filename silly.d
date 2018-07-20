module silly;

import std.experimental.logger;
import std.traits;
import std.typecons;
import std.algorithm;
import core.time;
import std.container.array;
import std.array;
import std.range;
import std.conv : to;
import std.stdio;
import std.concurrency;

__gshared SettingsImpl Settings;
__gshared TerminalImpl Terminal;

struct SettingsImpl {
	
}

shared static this() {
	import core.runtime;
	import std.getopt;
	import std.ascii;

	Terminal = TerminalImpl.create(ColourMode.init);

	auto args = Runtime.args;

	auto getoptResult = args.getopt(
		
	);

	if(getoptResult.helpWanted) {
		"Useful help message".writeln; // TODO

		import core.stdc.stdlib : exit;
		exit(0);
	}

	Runtime.extendedModuleUnitTester = () {
		executeUnitTests;
		return UnitTestResult(0,0,false,false);
	};
}

void executeUnitTests() {
	static if(!__traits(compiles, () {static import dub_test_root;}))
		static assert(false, "Couldn't find an entrypoint. Make sure you are running unittests with `dub test`");

	static import dub_test_root;

	auto scheduler = new FiberScheduler;
	size_t workerCount;
	scheduler.start({
		auto started = MonoTime.currTime;
		static foreach(module_; __traits(getMember, dub_test_root, "allModules")) {
			version(SillyDebug) pragma(msg, "silly | Looking for unittests in " ~ fullyQualifiedName!module_);
			static foreach(test; __traits(getUnitTests, module_)) {
				version(SillyDebug)
					pragma(msg, "silly | Found " ~ fullyQualifiedName!test ~ " named `" ~ getTestName!test ~ "`");
				++workerCount;
				spawn({
					ownerTid.send(executeTest!test);
				});
			}
		}

		Array!TestResult results;
		results.reserve(workerCount);

		foreach(i; 0..workerCount)
			results ~= receiveOnly!TestResult;

		results.listReporter;

		"Finished in %s".writefln(MonoTime.currTime - started);
	});
}

TestResult executeTest(alias test)() {
	TestResult ret = {
		fullName: fullyQualifiedName!test,
		testName: getTestName!test,
	};

	auto started = MonoTime.currTime;

	try {
		test();
		ret.duration = MonoTime.currTime - started;
		ret.succeed = true;
	} catch(Throwable t) {
		ret.duration = MonoTime.currTime - started;
		ret.succeed = false;

		foreach(th; t) {
			immutable(string)[] trace;
			foreach(i; th.info)
				trace ~= i.idup;

			ret.thrown ~= Thrown(th.message.idup, th.file, th.line, trace);
		}
	}

	return ret;
}

struct TestResult {
	string fullName;
	string testName;
	bool succeed;
	Duration duration;

	immutable(Thrown)[] thrown;
}

struct Thrown {
	string message;
	string file;
	size_t line;
	immutable(string)[] info;
}

void listReporter(Array!TestResult results) {
	foreach(result; results[].sort!((a, b) => a.fullName < b.fullName)) {
		Terminal.writeln(
			result.succeed ? Colourful("✓", Colour.ok) : Colourful("✗", Colour.achtung), " ",
			result.fullName.splitter('.').array[0..$-1].joiner(".").to!string, " ",
			result.testName, " ",
			result.duration,
		);

		foreach(th; result.thrown) {
			writefln!"%s(%d): %s"(th.file, th.line, th.message);
			foreach(tr; th.info)
				writefln!"%s"(tr);
		}
	}
}

string getTestName(alias test)() {
	string name = __traits(identifier, test);
	static foreach(attribute; __traits(getAttributes, test)) {
		static if(is(typeof(attribute) : string)) {
			name = attribute;
			goto done;
		}
	}

	done: return name;
}

enum Colour {
	ok = 32,
	lit = 35,
	achtung = 31,
}

enum ColourMode {
	automatic,
	always,
	iAmBoring,
}

struct Colourful {
	string text;
	Colour colour;
}

struct TerminalImpl {
	import core.stdc.stdlib;
	private {
		bool m_colourful;
	}

	static typeof(this) create(ColourMode mode) {
		TerminalImpl t;
		final switch(mode) with(ColourMode) {
		case automatic:
			version(Posix) {
				import core.sys.posix.unistd;
				t.m_colourful = isatty(STDOUT_FILENO) == 1;
			} else {
				t.m_colourful = false;
			}
			break;
		case always:
			t.m_colourful = true;
			break;
		case iAmBoring:
			t.m_colourful = false;
			break;
		}
		return t;
	}

	void writeln(ARGS...)(ARGS args) {
		static foreach(i, arg; args) {
			static if(is(typeof(arg) : Colourful)) {
				this.write(arg);
			} else {
				stdout.write(arg);
			}
		}

		stdout.writeln;
	}

	void write(Colourful c) {
		version(Posix) {
			stdout.writef("\033[0;%dm%s\033[m", c.colour, c.text);
		} else {
			stdout.write(c.text);
		}
	}
}