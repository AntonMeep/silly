module silly;

version(unittest):

static if(!__traits(compiles, () {static import dub_test_root;})) {
	static assert(false, "Couldn't find 'dub_test_root'. Make sure you are running tests with `dub test`");
} else {
	static import dub_test_root;
}

import core.runtime     : Runtime, UnitTestResult;
import core.time        : Duration, MonoTime, msecs;
import std.algorithm    : any, canFind, count, max;
import std.concurrency  : receive, send, spawn, thisTid, ownerTid, receiveOnly;
import std.format       : format;
import std.getopt       : getopt;
import std.meta         : Alias;
import std.parallelism  : TaskPool, totalCPUs;
import std.stdio        : stdout, writef, writeln, writefln;
import std.string       : indexOf, leftJustifier, lastIndexOf, lineSplitter;
import std.traits       : fullyQualifiedName, isAggregateType;

struct LoggerDone {}

shared static this() {
	Runtime.extendedModuleUnitTester = () {
		bool verbose;
		size_t passed, failed;
		uint threads = totalCPUs - 1;

		auto args = Runtime.args;
		auto getoptResult = args.getopt(
			"no-colours",
				"Disable colours",
				&noColours,
			"t|threads",
				"Number of threads to use. 1 to run in single thread",
				&threads,
			"v|verbose",
				"Show verbose output (full stack traces and durations)",
				&verbose,
		);

		if(getoptResult.helpWanted) {
			"Usage:\n\tdub test -- <options>\n\nOptions:".writefln;

			foreach(option; getoptResult.options)
				"  %s\t%s\t%s\n".writef(option.optShort, option.optLong.leftJustifier(20), option.help);

			return UnitTestResult(0, 0, false, false);
		}

		Console.init;

		Test[] tests;

		// Test discovery
		foreach(m; dub_test_root.allModules) {
			static if(__traits(compiles, __traits(getUnitTests, m)) &&
					!(__traits(isTemplate, m) || (__traits(compiles, isAggregateType!m) && isAggregateType!m))) {
				alias module_ = m;
			} else {
				// For cases when module contains member of the same name
				alias module_ = Alias!(__traits(parent, m));
			}

			// Unittests in the module
			foreach(test; __traits(getUnitTests, module_))
				tests ~= Test(fullyQualifiedName!test, getTestName!test, &test);

			// Unittests in structs and classes
			foreach(member; __traits(derivedMembers, module_)) {
				static if(__traits(compiles, __traits(parent, __traits(getMember, module_, member))) &&
					__traits(isSame, __traits(parent, __traits(getMember, module_, member)), module_) &&
					__traits(compiles, __traits(getUnitTests, __traits(getMember, module_, member)))) {
					foreach(test; __traits(getUnitTests, __traits(getMember, module_, member))) {
						tests ~= Test(fullyQualifiedName!test, getTestName!test, &test);
					}
				}
			}
		}

		auto loggerTid = spawn(&resultLogger, verbose);
		
		with(new TaskPool(threads)) {
			foreach(test; parallel(tests, 1))
				send(loggerTid, test.executeTest);

			finish(true);
		}

		send(loggerTid, LoggerDone());

		return receiveOnly!UnitTestResult;
	};
}

void resultLogger(bool verbose) {
	Duration totalDuration;
	size_t passed, failed;

	bool done = false;
	while(!done)
		receive(
			(TestResult result) {
				if(result.succeed) {
					Console.write(" ✓ ", Colour.ok, true);
					++passed;
				} else {
					Console.write(" ✗ ", Colour.achtung, true);
					++failed;
				}

				totalDuration += result.duration;

				Console.write(result.test.fullName[0..result.test.fullName.lastIndexOf('.')].truncateName(verbose), Colour.none, true);
				" %s".writef(result.test.testName);

				if(verbose) {
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
					if(verbose) {
						foreach(line; th.info)
							writeln("    ", line);
					} else {
						for(size_t i = 0; i < th.info.length && !th.info[i].canFind(__FILE__); ++i)
							writeln("    ", th.info[i]);
					}
					writeln("    -------------------");
				}
			},
			(LoggerDone _) {
				done = true;
				ownerTid.send(UnitTestResult(passed + failed, passed, false, false));
			},
		);

	writeln;
	Console.write("Summary: ", Colour.none, true);
	Console.write(passed, Colour.ok);
	" passed, ".writef;

	Console.write(failed, failed ? Colour.achtung : Colour.none);
	" failed in %d ms\n".writef(totalDuration.total!"msecs");
}

TestResult executeTest(Test test) {
	import core.exception : AssertError;
	auto ret = TestResult(test);

	void trace(Throwable t) {
		foreach(th; t) {
			immutable(string)[] trace;
			foreach(i; th.info)
				trace ~= i.idup;

			ret.thrown ~= Thrown(typeid(th).name, th.message.idup, th.file, th.line, trace);
		}
	}

	auto started = MonoTime.currTime;
	try {
		scope(exit) ret.duration = MonoTime.currTime - started;
		test.ptr();
		ret.succeed = true;
	} catch(Exception e) {
		trace(e);
	} catch(AssertError a) {
		trace(a);
	}

	return ret;
}

struct Test {
	string fullName,
		   testName;
	
	void function() ptr;
}

struct TestResult {
	Test test;
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

__gshared bool noColours;

enum Colour {
	none,
	ok = 32,
	// lit = 35,
	achtung = 31,
}

static struct Console {
	static void init() {
		if(!noColours) {
			version(Posix) {
				import core.sys.posix.unistd;
				noColours = isatty(STDOUT_FILENO) == 0;
				return;
			}
		}

		noColours = true;
	}

	static void write(T)(T t, Colour c = Colour.none, bool bright = false) {
		if(!noColours) {
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