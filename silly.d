module silly;

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
import std.format;

import core.stdc.stdlib : exit;

__gshared SettingsImpl Settings;

shared static this() {
	import core.runtime;
	import std.getopt;
	import std.ascii;

	auto args = Runtime.args;

	auto getoptResult = args.getopt(
		"colours",
			"Use colours (automatic, always or iAmBoring). Default is automatic",
			&Settings.colours,
		"traces",
			"Show traces (truncated, full or none). Default is truncated",
			&Settings.traces,
		"durations",
			"Show durations (longest, always or never). Default is longest",
			&Settings.durations,
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
		"Usage:\n\tdub test -- <options>\n".writeln;

		"Options:".writeln;

		import std.string : leftJustifier;
		getoptResult.options
			.each!(a => writefln!"  %s\t%s\t%s"(a.optShort, a.optLong.leftJustifier(10), a.help));

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

		if(results[].any!(a => !a.succeed))
			1.exit;
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
	foreach(result; results[].sort!((a, b) => a.fullName < b.fullName)) {
		result.succeed
			? colourWrite(" ✓ ", Colour.ok)
			: colourWrite(" ✗ ", Colour.achtung);
		
		result.fullName.splitter('.').array[0..$-1].joiner(".").brightWrite;
		write(" ", result.testName);

		final switch(Settings.durations) with(DurationMode) {
		case longest:
			if(result.duration >= 100.msecs)
				format!" (%d ms)"(result.duration.total!"msecs").colourWrite(Colour.achtung);
			break;
		case always:
			writef!" (%d ms)"(result.duration.total!"msecs");
			break;
		case never:
			break;
		}

		writeln;

		foreach(th; result.thrown) {
			writefln!"    %s has been thrown from %s:%d `%s`"(th.type, th.file, th.line, th.message);

			final switch(Settings.traces) with(TraceMode) {
			case truncated:
				writeln("    --- Trace ---");
				th.info.until!(a => a.startsWith(__FILE__)).each!(a => writeln("    ", a));
				writeln("    -------------");
				break;
			case full:
				writeln("    --- Trace ---");
				th.info.each!(a => writeln("    ", a));
				writeln("    -------------");
				break;
			case none:
				break;
			}
		}
	}
}

struct SettingsImpl {
	ColourMode   colours;
	TraceMode    traces;
	DurationMode durations;
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