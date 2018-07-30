module basic.simple;

enum hello = "Hello, world!";

@("Always successful test")
unittest {
	assert(hello == "Hello, world!");
}

@("Always failing test")
unittest {
	assert(hello == "Hello there!");
}