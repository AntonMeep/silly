/+
dub.json:
{
	"name": "generate"
}
+/

import std.format;
import std.string;
import std.file;
import std.conv : to;

enum TEMPLATE = q"EOS
module %1$s;

import std.exception : enforce;

enum NUMBER_OF_BOTTLES = %2$d;

enum BOTTLES = "%2$d bottle%3$s of beer on the wall\n%2$d bottle%3$s of beer\nTake one down, pass it around";

unittest {
	enforce(NUMBER_OF_BOTTLES == %2$d);
}

EOS";

enum APP = q"EOS
module app;

void main() {
	import std.stdio;

	string[] bottles;

	%-(
		
	%)

	foreach(bottle; bottles)
		writeln(bottle);
}
EOS";

void main() {
	string directory = "source/";
	string[] modules;

	directory.mkdir;

	foreach_reverse(i; 1..100) {
		directory ~= "_%d_bottle%s/".format(i, i == 1 ? "" : "s");
		directory.mkdir;

		modules ~= directory["source/".length..$].tr("/", ".")[0..$-1] ~ ".beer";

		write(directory ~ "/beer.d", format!TEMPLATE(modules[$-1], i, i == 1 ? "" : "s"));
	}

	"source/app.d".write("module app;\nimport std.stdio;\nversion(unittest) {} else void main() {\n\tstring[] bottles;\n");
	foreach(m; modules)
		"source/app.d".append(format!"\t{ import %s; bottles ~= BOTTLES; }\n"(m));
	"source/app.d".append("\tforeach(b; bottles) writeln(b);\n}");
}