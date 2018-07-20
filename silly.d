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

__gshared Settings globalSettings;

struct Settings {
	bool parallel = true;
}

shared static this() {
	import core.runtime;
	import std.getopt;
	import std.ascii;

	auto args = Runtime.args;

	auto getoptResult = args.getopt(
		"parallel", "execute tests in parallel. default: true", &globalSettings.parallel,
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

		auto reporter = ListReporter();

		foreach_reverse(i; 0..workerCount)
			reporter.add(receiveOnly!TestResult);
		
		reporter.finalize;
		"Finished in %s".writefln(MonoTime.currTime - started);
	});
}

TestResult executeTest(alias test)() {
	TestResult ret = {
		fullName: fullyQualifiedName!test,
		testName: getTestName!test,
		sourceLine: __traits(identifier, test).find("L").drop(1).until('_').to!size_t,
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
		// ret.thrown = t;
	}

	return ret;
}

struct TestResult {
	string fullName;
	string testName;
	size_t sourceLine;
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

struct ListReporter {
	private {
		Array!TestResult m_results;

		enum m_passed = "✓";
		enum m_failed = "✗";
	}

	void add(TestResult t) {
		m_results ~= t;
	}

	void finalize() {
		foreach(result; m_results) {
			writefln!"%s %s `%s` located on line %d in %s"(
				result.succeed
					? m_passed
					: m_failed,
				result.fullName.splitter('.').array[0..$-1].joiner(".").to!string,
				result.testName,
				result.sourceLine,
				result.duration,
			);
			foreach(th; result.thrown) {
				writefln!"%s(%d): %s"(th.file, th.line, th.message);
				foreach(tr; th.info)
					writefln!"%s"(tr);
			}
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