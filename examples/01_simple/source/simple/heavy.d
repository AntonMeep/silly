module simple.heavy;

import core.time;

@("Heavily utilizes single CPU core")
unittest {
	int a;
	auto started = MonoTime.currTime;
	while(true) {
		a = a + 1;
		if(MonoTime.currTime - started >= 3.seconds)
			break;
	}
}