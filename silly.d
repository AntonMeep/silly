module silly;

version(unittest):

static if(!__traits(compiles, () {static import dub_test_root;}))
	static assert(false, "silly | Couldn't find 'dub_test_root'. Make sure you are running tests with `dub test`");

static import dub_test_root;

import core.stdc.stdlib : exit;
import core.time        : Duration, MonoTime, msecs;
import std.algorithm    : any, canFind, count, max, sort;
import std.concurrency  : FiberScheduler, spawn, ownerTid, send, receiveOnly;
import std.meta         : Alias;
import std.stdio        : stdout, writef, writeln, writefln;
import std.string       : indexOf, leftJustifier, lastIndexOf, lineSplitter;
import std.traits       : fullyQualifiedName;

shared static this() {
	import core.runtime : Runtime, UnitTestResult;
	import std.getopt : getopt;

	auto args = Runtime.args;

	auto getoptResult = args.getopt(
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
	);

	if(getoptResult.helpWanted) {
		"Usage:\n\tdub test -- <options>\n\nOptions:".writefln;

		foreach(option; getoptResult.options)
			"  %s\t%s\t%s\n".writef(option.optShort, option.optLong.leftJustifier(10), option.help);

		exit(0);
	}

	Runtime.extendedModuleUnitTester = () {
		executeUnitTests;
		return UnitTestResult(0,0,false,false);
	};
}

void executeUnitTests() {
	size_t workerCount;
	new FiberScheduler().start({
		auto started = MonoTime.currTime;
		static foreach(m; dub_test_root.allModules) {
			static if(__traits(compiles, __traits(getUnitTests, m)) && !__traits(isTemplate, m)) {
				alias module_ = m;
			} else {
				// For cases when module contains member of the same name
				alias module_ = Alias!(__traits(parent, m));
			}

			static foreach(test; __traits(getUnitTests, module_)) {
				++workerCount;
				spawn({
					ownerTid.send(executeTest!test);
				});
			}

			version(SillyDebug)
				pragma(msg, "silly | Module ", fullyQualifiedName!module_, " contains ", cast(int) __traits(getUnitTests, module_).length, " unittests");
		}

		TestResult[] results = new TestResult[workerCount];

		foreach(i; 0..workerCount)
			results[i] = receiveOnly!TestResult;

		auto totalDuration = MonoTime.currTime - started;

		Console.init;

		results.listReporter;

		auto passed = results.count!(a => a.succeed);
		auto failed = results.length - passed;

		writeln;
		Console.write("Summary: ", Colour.none, true);
		Console.write(passed, Colour.ok);
		" passed, ".writef;

		Console.write(failed, failed ? Colour.achtung : Colour.none);
		" failed in %d ms\n".writef(totalDuration.total!"msecs");

		if(failed)
			exit(1);
	});
}

TestResult executeTest(alias test)() {
	import core.exception : AssertError;
	auto ret = TestResult(fullyQualifiedName!test, getTestName!test);

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
		scope(exit) ret.duration = MonoTime.currTime - started;
		test();
		ret.succeed = true;
	} catch(Exception e) {
		trace(e);
	} catch(AssertError a) {
		trace(a);
	}

	return ret;
}

struct TestResult {
	string fullName,
		   testName;
	bool succeed;
	Duration duration;

	immutable(Thrown)[] thrown;
}

struct Thrown {
	string type,
		   message,
		   file;
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
	bool fullStackTraces,
		 showDurations,
		 verbose;
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