module silly;

version(unittest):

static if(!__traits(compiles, () {static import dub_test_root;})) {
	static assert(false, "Couldn't find 'dub_test_root'. Make sure you are running tests with `dub test`");
} else {
	static import dub_test_root;
}

import core.stdc.stdlib : exit;
import core.time        : Duration, MonoTime, msecs;
import std.algorithm    : any, canFind, count, max;
import std.concurrency  : FiberScheduler, spawn, ownerTid, send, receiveOnly;
import std.format       : format;
import std.meta         : Alias;
import std.stdio        : stdout, writef, writeln, writefln;
import std.string       : indexOf, leftJustifier, lastIndexOf, lineSplitter;
import std.traits       : fullyQualifiedName;

shared static this() {
	import core.runtime : Runtime, UnitTestResult;
	import std.getopt : getopt;

	Runtime.extendedModuleUnitTester = () {
		bool fullStackTraces, showDurations, verbose;

		auto args = Runtime.args;
		auto getoptResult = args.getopt(
			"no-colours",
				"Disable colours",
				(string o) { useColours = false; },
			"full-traces",
				"Show full stack traces. By default traces are truncated",
				&fullStackTraces,
			"show-durations",
				"Show durations for all unit tests. Default is false",
				&showDurations,
			"verbose",
				"Show verbose output",
				(string o) { verbose = fullStackTraces = showDurations = true; }
		);

		if(getoptResult.helpWanted) {
			"Usage:\n\tdub test -- <options>\n\nOptions:".writefln;

			foreach(option; getoptResult.options)
				"  %s\t%s\t%s\n".writef(option.optShort, option.optLong.leftJustifier(20), option.help);

			exit(0);
		}

		Console.init;

		new FiberScheduler().start({
			size_t workerCount, passed, failed;

			// Test discovery
			foreach(m; dub_test_root.allModules) {
				static if(__traits(compiles, __traits(getUnitTests, m)) && !__traits(isTemplate, m)) {
					alias module_ = m;
				} else {
					// For cases when module contains member of the same name
					alias module_ = Alias!(__traits(parent, m));
				}

				// Unittests in the module
				static foreach(test; __traits(getUnitTests, module_)) {
					++workerCount;
					spawn({
						ownerTid.send(executeTest!test);
					});
				}

				// Unittests in structs and classes
				static foreach(member; __traits(derivedMembers, module_)) {
					static if(__traits(compiles, __traits(parent, __traits(getMember, module_, member))) &&
							  __traits(isSame, __traits(parent, __traits(getMember, module_, member)), module_)) {
						static foreach(test; __traits(getUnitTests, __traits(getMember, module_, member))) {
							++workerCount;
							spawn({
								ownerTid.send(executeTest!test);
							});
						}
					}
				}
			}

			// Result reporter
			Duration totalDuration;
			foreach(unused; 0..workerCount) {
				auto result = receiveOnly!TestResult;

				totalDuration += result.duration;

				if(result.succeed) {
					Console.write(" ✓ ", Colour.ok, true);
					++passed;
				} else {
					Console.write(" ✗ ", Colour.achtung, true);
					++failed;
				}
				
				Console.write(result.fullName[0..result.fullName.lastIndexOf('.')].truncateName(verbose), Colour.none, true);
				" %s".writef(result.testName);

				if(showDurations) {
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
					if(fullStackTraces) {
						foreach(line; th.info)
							writeln("    ", line);
					} else {
						for(size_t i = 0; i < th.info.length && !th.info[i].canFind(__FILE__); ++i)
							writeln("    ", th.info[i]);
					}
					writeln("    -------------------");
				}
			}

			writeln;
			Console.write("Summary: ", Colour.none, true);
			Console.write(passed, Colour.ok);
			" passed, ".writef;

			Console.write(failed, failed ? Colour.achtung : Colour.none);
			" failed in %d ms\n".writef(totalDuration.total!"msecs");

			if(failed)
				exit(1);
		});

		return UnitTestResult(0,0,false,false);
	};
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

static bool useColours = true;

enum Colour {
	none,
	ok = 32,
	// lit = 35,
	achtung = 31,
}

static struct Console {
	static void init() {
		if(useColours) {
			version(Posix) {
				import core.sys.posix.unistd;
				useColours = isatty(STDOUT_FILENO) != 0;
				return;
			}
		}

		useColours = false;
	}

	static void write(T)(T t, Colour c = Colour.none, bool bright = false) {
		if(useColours) {
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

string truncateName(string s, bool verbose = false) {
	return s.length > 30 && !verbose
		? s[max(s.indexOf('.', s.length - 30), s.length - 30) .. $]
		: s;
}