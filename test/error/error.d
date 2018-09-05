module error;

@("just fine")
unittest { }

@("assert fails, nothing horrible happens")
unittest {
	assert(false);
}

@("OH NO WE ARE GOING TO DIE (not really, just throwing RangeError)")
unittest {
	import core.exception : RangeError;
	throw new RangeError("not a real error");
}

@("still fine")
unittest { }

@("fine")
unittest { }