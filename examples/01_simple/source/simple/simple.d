module simple.simple;

import std.exception : enforce;

enum hello = "Hello, world!";

@("Always successful test")
unittest {
	enforce(hello == "Hello, world!");
}

@("Always failing test")
unittest {
	enforce(hello == "Hello there!");
}