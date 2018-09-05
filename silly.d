module silly;

version(unittest):

static if(!__traits(compiles, () {static import dub_test_root;})) {
	static assert(false, "Couldn't find 'dub_test_root'. Make sure you are running tests with `dub test`");
} else {
	static import dub_test_root;
}

import core.atomic      : atomicOp;
import core.runtime     : Runtime, UnitTestResult;
import core.time        : Duration, MonoTime;
import std.getopt       : getopt;
import std.parallelism  : TaskPool, totalCPUs;
import std.stdio        : stdout, writef, writeln, writefln;

shared static this() {
	Runtime.extendedModuleUnitTester = () {
		bool verbose;
		shared size_t passed, failed;
		uint threads;
		string include, exclude;

		auto args = Runtime.args;
		auto getoptResult = args.getopt(
			"no-colours",
				"Disable colours",
				&noColours,
			"t|threads",
				"Number of worker threads. 0 to auto-detect (default)",
				&threads,
			"i|include",
				"Run tests if their name matches specified regular expression",
				&include,
			"e|exclude",
				"Skip tests if their name matches specified regular expression",
				&exclude,
			"v|verbose",
				"Show verbose output (full stack traces and durations)",
				&verbose,
		);

		if(getoptResult.helpWanted) {
			import std.string : leftJustifier;

			"Usage:\n\tdub test -- <options>\n\nOptions:".writefln;

			foreach(option; getoptResult.options)
				"  %s\t%s\t%s\n".writef(option.optShort, option.optLong.leftJustifier(20), option.help);

			return UnitTestResult(0, 0, false, false);
		}

		if(!threads)
			threads = totalCPUs;

		Console.init;

		Test[] tests;

		// Test discovery
		foreach(m; dub_test_root.allModules) {
			import std.traits : fullyQualifiedName, isAggregateType;
			static if(__traits(compiles, __traits(getUnitTests, m)) &&
					!(__traits(isTemplate, m) || (__traits(compiles, isAggregateType!m) && isAggregateType!m))) {
				alias module_ = m;
			} else {
				import std.meta : Alias;
				// For cases when module contains member of the same name
				alias module_ = Alias!(__traits(parent, m));
			}

			// Unittests in the module
			foreach(test; __traits(getUnitTests, module_))
				tests ~= Test(fullyQualifiedName!test, getTestName!test, &test);

			// Unittests in structs and classes
			foreach(member; __traits(derivedMembers, module_))
				static if(__traits(compiles, __traits(parent, __traits(getMember, module_, member))) &&
					__traits(isSame, __traits(parent, __traits(getMember, module_, member)), module_) &&
					__traits(compiles, __traits(getUnitTests, __traits(getMember, module_, member))))
						foreach(test; __traits(getUnitTests, __traits(getMember, module_, member)))
							tests ~= Test(fullyQualifiedName!test, getTestName!test, &test);
		}

		auto started = MonoTime.currTime;

		with(new TaskPool(threads-1)) {
			import std.regex : matchFirst;
			foreach(test; parallel(tests)) {
				if((!include && !exclude) ||
					(include && !(test.fullName ~ " " ~ test.testName).matchFirst(include).empty) ||
					(exclude &&  (test.fullName ~ " " ~ test.testName).matchFirst(exclude).empty)) {
						auto result = test.executeTest;
						result.writeResult(verbose);

						atomicOp!"+="(result.succeed ? passed : failed, 1UL);
				}
			}

			finish(true);
		}

		writeln;
		Console.write("Summary: ", Colour.none, true);
		Console.write(passed, Colour.ok);
		" passed, ".writef;

		Console.write(failed, failed ? Colour.achtung : Colour.none);
		" failed in %d ms\n".writef((MonoTime.currTime - started).total!"msecs");

		return UnitTestResult(passed + failed, passed, false, false);
	};
}

void writeResult(TestResult result, in bool verbose) {
	import std.algorithm : canFind;
	import std.range     : drop;
	import std.string    : lastIndexOf, lineSplitter;

	stdout.lock;
	scope(exit) stdout.unlock;

	result.succeed
		? Console.write(" ✓ ", Colour.ok, true)
		: Console.write(" ✗ ", Colour.achtung, true);

	Console.write(result.test.fullName[0..result.test.fullName.lastIndexOf('.')].truncateName(verbose), Colour.none, true);
	" %s".writef(result.test.testName);

	if(verbose)
		" (%.3f ms)".writef((cast(real) result.duration.total!"usecs") / 10.0f ^^ 3);

	writeln;

	foreach(th; result.thrown) {
		"    %s@%s(%d): %s".writefln(th.type, th.file, th.line, th.message.lineSplitter.front);
		foreach(line; th.message.lineSplitter.drop(1))
			"      %s".writefln(line);

		writeln("    --- Stack trace ---");
		if(verbose) {
			foreach(line; th.info)
				writeln("    ", line);
		} else {
			for(size_t i = 0; i < th.info.length && !th.info[i].canFind(__FILE__); ++i)
				writeln("    ", th.info[i]);
		}
	}
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
	achtung = 31,
}

static struct Console {
	static void init() {
		if(noColours) {
			return;
		} else {
			version(Posix) {
				import core.sys.posix.unistd;
				noColours = isatty(STDOUT_FILENO) == 0;
			} else version(Windows) {
				import core.sys.windows.winbase : GetStdHandle, STD_OUTPUT_HANDLE, INVALID_HANDLE_VALUE;
				import core.sys.windows.wincon  : SetConsoleOutputCP, GetConsoleMode, SetConsoleMode;
				import core.sys.windows.windef  : DWORD;
				import core.sys.windows.winnls  : CP_UTF8;

				SetConsoleOutputCP(CP_UTF8);

				auto hOut = GetStdHandle(STD_OUTPUT_HANDLE);
				DWORD originalMode;

				// TODO: 4 stands for ENABLE_VIRTUAL_TERMINAL_PROCESSING which should be
				// in druntime v2.082.0
				noColours = hOut == INVALID_HANDLE_VALUE           ||
							!GetConsoleMode(hOut, &originalMode)   ||
							!SetConsoleMode(hOut, originalMode | 4);
			}
		}
	}

	static void write(T)(T t, Colour c = Colour.none, bool bright = false) {
		void cwrite() {
			if(c == Colour.none && bright) {
				stdout.writef("\033[1m%s\033[m", t);
			} else {
				stdout.writef("\033[%d;%dm%s\033[m", bright, c, t);
			}
		}

		if(noColours) {
			stdout.write(t);
		} else {
			version(Posix) {
				cwrite();
			} else version(Windows) {
				cwrite();
			}
		}
	}
}

string getTestName(alias test)() {
	string name = __traits(identifier, test);

	foreach(attribute; __traits(getAttributes, test)) {
		if(is(typeof(attribute) : string)) {
			name = attribute;
			break;
		}
	}

	return name;
}

string truncateName(string s, bool verbose = false) {
	import std.algorithm : max;
	import std.string    : indexOf;
	return s.length > 30 && !verbose
		? s[max(s.indexOf('.', s.length - 30), s.length - 30) .. $]
		: s;
}