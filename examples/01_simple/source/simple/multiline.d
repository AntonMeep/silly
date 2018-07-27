module simple.multiline;

@("This unittest throws an exception with multi-line message")
unittest {
	throw new Exception("Hello,\nWorld!");
}