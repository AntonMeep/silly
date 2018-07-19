module simple.sleepy;

import core.time;
import core.thread;

@("Waits for a moment and succeeds")
unittest {
	Thread.getThis.sleep(500.msecs);
}

@("Waits for a moment and fails")
unittest {
	Thread.getThis.sleep(500.msecs);
	throw new Exception("Nope");
}