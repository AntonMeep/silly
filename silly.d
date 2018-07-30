module silly;

version(unittest):

import core.stdc.stdlib : exit;
import core.time        : Duration, MonoTime, msecs;
import std.algorithm    : any, canFind, count, max, sort;
import std.concurrency  : FiberScheduler, spawn, ownerTid, send, receiveOnly;
import std.stdio        : stdout, writef, writeln, writefln;
import std.string       : indexOf, leftJustifier, lastIndexOf, lineSplitter;
import std.traits       : fullyQualifiedName;

shared static this() {
	import core.runtime : Runtime, UnitTestResult;
	import std.getopt : getopt;

	auto args = Runtime.args;

	// That's kinda ugly, but it works and makes code shorter
	with(args.getopt(
		"no-colours",
			"Disable colours",
			(string o) { Settings.useColours = false; },
		"full-traces",
			"Show full stack traces. By default traces are truncated",
			&Settings.fullStackTraces,
		"show-durations",
			"Show durations for all unit tests. Default is false",
			&Settings.showDurations,
		"verbose",
			"Show verbose output",
			(string o) { Settings.verbose = Settings.fullStackTraces = Settings.showDurations = true; }
	))
		if(helpWanted) {
			"Usage:\n\tdub test -- <options>\n\nOptions:".writefln;

			foreach(option; options)
				"  %s\t%s\t%s\n".writef(option.optShort, option.optLong.leftJustifier(10), option.help);

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

	size_t workerCount;
	new FiberScheduler().start({
		auto started = MonoTime.currTime;
		static foreach(m; __traits(getMember, dub_test_root, "allModules")) {
			static if(__traits(compiles, __traits(getUnitTests, m)) && !__traits(isTemplate, m)) {
				static foreach(test; __traits(getUnitTests, m)) {
					++workerCount;
					spawn({
						ownerTid.send(executeTest!test);
					});
				}

				version(SillyDebug)
					pragma(msg, "silly | Module ", fullyQualifiedName!m, " contains ", cast(int) __traits(getUnitTests, m).length, " unittests");
			} else {
				// For the rare cases when module contains member of the same name
				// This is an ugly fix (copy-pasta), but it works
				// See issue #5 for more info
				static foreach(test; __traits(getUnitTests, __traits(parent, m))) {
					++workerCount;
					spawn({
						ownerTid.send(executeTest!test);
					});
				}

				version(SillyDebug)
					pragma(msg, "silly | Module ", fullyQualifiedName!(__traits(parent, m)), " contains ", cast(int) __traits(getUnitTests, __traits(parent, m)).length, " unittests");
			}
		}

		TestResult[] results;
		results.reserve(workerCount);

		foreach(i; 0..workerCount)
			results ~= receiveOnly!TestResult;

		auto totalDuration = MonoTime.currTime - started;

		Console.init;

		results.listReporter;

		auto passed = results[].count!(a => a.succeed);
		auto failed = results.length - passed;

		writeln;
		Console.write("Summary: ", Colour.none, true);
		Console.write(passed, Colour.ok); " passed, ".writef;
		if(failed) {
			Console.write(failed, Colour.achtung);
		} else {
			"%d".writef(failed);
		}
		" failed in %d ms\n".writef(totalDuration.total!"msecs");

		foreach(result; results)
			if(!result.succeed)
				exit(1);
	});
}

TestResult executeTest(alias test)() {
	import core.exception : AssertError;
	TestResult ret = {
		fullName: fullyQualifiedName!test,
		testName: getTestName!test,
	};

	auto started = MonoTime.currTime;

	void trace(Throwable t) {
		foreach(th; t) {
			immutable(string)[] trace;
			foreach(i; th.info)
				trace ~= i.idup;

			ret.thrown ~= Thrown(typeid(th).name, th.message.idup, th.file, th.line, trace);
		}
	}

	try {
		test();
		ret.duration = MonoTime.currTime - started;
		ret.succeed = true;
	} catch(Exception e) {
		trace(e);
	} catch(AssertError a) {
		trace(a);
	} finally {
		ret.duration = MonoTime.currTime - started;
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
	string type;
	string message;
	string file;
	size_t line;
	immutable(string)[] info;
}

void listReporter(ref TestResult[] results) {
	import std.format : format;
	foreach(result; results.sort!((a, b) => a.fullName < b.fullName)) {
		result.succeed
			? Console.write(" ✓ ", Colour.ok, true)
			: Console.write(" ✗ ", Colour.achtung, true);
		
		Console.write(result.fullName[0..result.fullName.lastIndexOf('.')].truncateName, Colour.none, true);
		" %s".writef(result.testName);

		if(Settings.showDurations) {
			" (%d ms)".writef(result.duration.total!"msecs");
		} else if(result.duration >= 100.msecs) {
			Console.write(" (%d ms)".format(result.duration.total!"msecs"), Colour.achtung);
		}

		writeln;

		foreach(th; result.thrown) {
			"    %s has been thrown from %s:%d with the following message:"
				.writefln(th.type, th.file, th.line);
			foreach(line; th.message.lineSplitter)
				"      ".writeln(line);

			
			writeln("    --- Stack trace ---");
			if(Settings.fullStackTraces) {
				foreach(line; th.info)
					writeln("    ", line);
			} else {
				for(size_t i = 0; i < th.info.length && !th.info[i].canFind(__FILE__); ++i)
					writeln("    ", th.info[i]);
			}
			writeln("    -------------------");
		}
	}
}

static struct Settings {
static:
	bool useColours      = true;
	bool fullStackTraces = false;
	bool showDurations   = false;
	bool verbose         = false;
}

enum Colour {
	none,
	ok = 32,
	// lit = 35,
	achtung = 31,
}

static struct Console {
static:
	void init() {
		if(Settings.useColours) {
			version(Posix) {
				import core.sys.posix.unistd;
				Settings.useColours = isatty(STDOUT_FILENO) != 0;
				return;
			}
		}
		
		Settings.useColours = false;
	}

	void write(T)(T t, Colour c = Colour.none, bool bright = false) {
		if(Settings.useColours) {
			version(Posix) {
				if(c == Colour.none && bright) {
					stdout.writef("\033[1m%s\033[m", t);
				} else {
					stdout.writef("\033[%d;%dm%s\033[m", bright, c, t);
				}
				return;
			}
		}
		
		stdout.write(t);
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

string truncateName(string s) {
	return s.length > 30 && !Settings.verbose
		? s[max(s.indexOf('.', s.length - 30), s.length - 30) .. $]
		: s;
}