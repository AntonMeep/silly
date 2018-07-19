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

shared static this() {
	import core.runtime;

	Runtime.extendedModuleUnitTester = () {
		executeUnitTests;
		return UnitTestResult(0,0,false,false);
	};
}

void executeUnitTests() {
	static if(!__traits(compiles, () {static import dub_test_root;}))
		static assert(false, "Couldn't find an entrypoint. Make sure you are running unittests with `dub test`");

	static import dub_test_root;

	auto reporter = ListReporter();

	static foreach(module_; __traits(getMember, dub_test_root, "allModules")) {
		version(SillyDebug) pragma(msg, "silly | Looking for unittests in " ~ fullyQualifiedName!module_);
		static foreach(test; __traits(getUnitTests, module_)) {
			version(SillyDebug)
				pragma(msg, "silly | Found " ~ fullyQualifiedName!test ~ " named `" ~ getTestName!test ~ "`");

			reporter.add(executeTest!test);
		}
	}

	reporter.finalize;
}

TestResult executeTest(alias test)() {
	TestResult ret = TestResult(
		fullyQualifiedName!test,
		getTestName!test,
		__traits(identifier, test).find("L").drop(1).until('_').to!size_t,
	);

	auto started = MonoTime.currTime;

	try {
		test();
		ret.duration = MonoTime.currTime - started;
		ret.succeed = true;
	} catch(Throwable t) {
		ret.duration = MonoTime.currTime - started;
		ret.succeed = false;
		ret.thrown = t;
	}

	return ret;
}

struct TestResult {
	string fullName;
	string testName;
	size_t sourceLine;
	bool succeed;
	Throwable thrown;
	Duration duration;
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
		foreach(result; m_results)
			writefln!"%s %s `%s` located on line %d in %s"(
				result.succeed
					? m_passed
					: m_failed,
				result.fullName.splitter('.').array[0..$-1].joiner(".").to!string,
				result.testName,
				result.sourceLine,
				result.duration,
			);
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