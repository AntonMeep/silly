module silly;

version(unittest):

import core.stdc.stdlib    : exit;
import core.time           : Duration, MonoTime;
import std.container.array : Array;
import std.traits          : fullyQualifiedName;

import std.concurrency;
import std.stdio;

shared static this() {
	import core.runtime : Runtime, UnitTestResult;
	import std.getopt : getopt;

	auto args = Runtime.args;

	auto getoptResult = args.getopt(
		"colours",
			"Use colours (automatic, always or iAmBoring). Default is automatic",
			&Settings.colours,
		"traces",
			"Show traces (truncated, full or none). Default is truncated",
			&Settings.traces,
		"show-durations",
			"Show durations for all unit tests. Default is false",
			&Settings.showDurations,
	);

	if(Settings.colours == ColourMode.automatic) {
		version(Posix) {
			import core.sys.posix.unistd;
			Settings.colours = isatty(STDOUT_FILENO) == 1 ? ColourMode.always : ColourMode.iAmBoring;
		} else {
			Settings.colours = ColourMode.iAmBoring;
		}
	}

	if(getoptResult.helpWanted) {
		"Usage:\n\tdub test -- <options>\n\nOptions:".writeln;

		import std.string : leftJustifier;
		foreach(option; getoptResult.options)
			"  %s\t%s\t%s".writefln(option.optShort, option.optLong.leftJustifier(10), option.help);

		exit(0);
	}

	Runtime.extendedModuleUnitTester = () {
		executeUnitTests;
		return UnitTestResult(0,0,false,false);
	};
}

void executeUnitTests() {
	import std.algorithm : any, count;

	static if(!__traits(compiles, () {static import dub_test_root;}))
		static assert(false, "Couldn't find an entrypoint. Make sure you are running unittests with `dub test`");

	static import dub_test_root;

	auto scheduler = new FiberScheduler;
	size_t workerCount;
	scheduler.start({
		auto started = MonoTime.currTime;
		static foreach(module_; __traits(getMember, dub_test_root, "allModules")) {
			static foreach(test; __traits(getUnitTests, module_)) {
				++workerCount;
				spawn({
					ownerTid.send(executeTest!test);
				});
			}

			version(SillyDebug)
				pragma(msg,
					"silly | Module ",
					fullyQualifiedName!module_.truncateName,
					" contains ",
					cast(int) __traits(getUnitTests, module_).length,
					" unittests");
		}

		Array!TestResult results;
		results.reserve(workerCount);

		foreach(i; 0..workerCount)
			results ~= receiveOnly!TestResult;

		auto totalDuration = MonoTime.currTime - started;

		results.listReporter;

		auto passed = results[].count!(a => a.succeed);
		auto failed = results.length - passed;

		writeln;
		"Summary: ".brightWrite;
		passed.colourWrite(Colour.ok); " passed, ".write;
		if(failed) {
			failed.colourWrite(Colour.achtung);
		} else {
			failed.write;
		}
		" failed in %d ms".writefln(totalDuration.total!"msecs");

		foreach(result; results)
			if(!result.succeed)
				exit(1);
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
	} catch(Exception t) {
		ret.duration = MonoTime.currTime - started;
		ret.succeed = false;

		foreach(th; t) {
			immutable(string)[] trace;
			foreach(i; th.info)
				trace ~= i.idup;

			ret.thrown ~= Thrown(typeid(th).name, th.message.idup, th.file, th.line, trace);
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
	string type;
	string message;
	string file;
	size_t line;
	immutable(string)[] info;
}

void listReporter(Array!TestResult results) {
	import core.time     : msecs;
	import std.algorithm : sort, startsWith;
	import std.format    : format;
	import std.string    : lastIndexOf;
	foreach(result; results[].sort!((a, b) => a.fullName < b.fullName)) {
		result.succeed
			? colourWrite(" ✓ ", Colour.ok)
			: colourWrite(" ✗ ", Colour.achtung);
		
		result.fullName[0..result.fullName.lastIndexOf('.')].truncateName.brightWrite;
		write(" ", result.testName);

		if(Settings.showDurations) {
			" (%d ms)".writef(result.duration.total!"msecs");
		} else {
			if(result.duration >= 100.msecs)
				" (%d ms)".format(result.duration.total!"msecs").colourWrite(Colour.achtung);
		}

		writeln;

		foreach(th; result.thrown) {
			"    %s has been thrown from %s:%d `%s`".writefln(th.type, th.file, th.line, th.message);

			final switch(Settings.traces) with(TraceMode) {
			case truncated:
				writeln("    --- Trace ---");
				for(size_t i = 0; i <= th.info.length && !th.info[i].startsWith(__FILE__); ++i)
					writeln("    ", th.info[i]);
				writeln("    -------------");
				break;
			case full:
				writeln("    --- Trace ---");
				foreach(line; th.info)
					writeln("    ", line);
				writeln("    -------------");
				break;
			case none:
				break;
			}
		}
	}
}

static struct Settings {
static:
	ColourMode colours;
	TraceMode  traces;
	bool       showDurations;
}

enum ColourMode {
	automatic,
	always,
	iAmBoring,
}

enum TraceMode {
	truncated,
	full,
	none,
}

enum DurationMode {
	longest,
	always,
	never,
}

enum Colour {
	none,
	ok = 32,
	lit = 35,
	achtung = 31,
}

void colourWrite(T)(T t, Colour c)
in(Settings.colours != ColourMode.automatic) {
	if(Settings.colours == ColourMode.always) {
		version(Posix) {
			stdout.writef("\033[0;%dm%s\033[m", c, t);
		} else {
			stdout.write(t);
		}
	} else {
		stdout.write(t);
	}
}

void brightWrite(T)(T t, Colour c = Colour.none)
in(Settings.colours != ColourMode.automatic) {
	if(Settings.colours == ColourMode.always) {
		version(Posix) {
			if(c == Colour.none) {
				stdout.writef("\033[1m%s\033[m", t);
			} else {
				stdout.writef("\033[1;%dm%s\033[m", c, t);
			}
		} else {
			stdout.write(t);
		}
	} else {
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
	import std.string : indexOf;
	if(s.length > 30) {
		auto i = s.indexOf('.', s.length - 30);
		return s[i == -1 ? $-30 : i .. $];
	}

	return s;
}