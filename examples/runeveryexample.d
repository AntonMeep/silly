#!/usr/bin/env dub
/+
dub.json:
{
	"name": "runeveryexample",
	"description": "Runs every example"
}
+/

module runeveryexample;

import std.algorithm : sort;
import std.array     : array;
import std.file      : exists, getcwd, dirEntries, SpanMode;
import std.path      : buildPath, baseName;
import std.process   : spawnProcess, Config, wait;
import std.stdio;

void main() {
	foreach(string example; getcwd.dirEntries("??_*", SpanMode.shallow).array.sort) {
		if(example.buildPath("generate.d").exists) {
			"--------> Generating sources for %s using generate.d".writefln(example.baseName);
			["dub", "generate.d"].spawnProcess(stdin, stdout, stderr, null, Config.none, example).wait;
		}
		"--------> Running example %s".writefln(example.baseName);
		["dub", "test"].spawnProcess(stdin, stdout, stderr, null, Config.none, example).wait;
	}
}
