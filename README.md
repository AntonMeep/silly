silly [![Lines of code](https://ohboi.gitlab.io/silly/loc.svg)](https://gitlab.com/ohboi/silly/blob/master/silly.d) [![pipeline status](https://gitlab.com/ohboi/silly/badges/master/pipeline.svg)](https://gitlab.com/ohboi/silly/commits/master)
=====

**silly** is a no-nonsense test runner for the D programming language. Instead of re-inventing the wheel and adding more and more levels of abstraction it just works, requiring as little effort from the programmer as possible.

## Why?

Built-in test runner is not good enough. It does its job, but it doesn't show what tests were executed. It just runs them all stopping on the first failed one. Of course, community offers many different solutions for that problem. Being an overcomplicated projects with thousands lines of code they could make you *less* productive increasing build times and deeply integrating into your project.

**silly** is developed with strict principles in mind.

### Keep It Simple, Silly

Find -> run -> report. That's all there is about test runners. It can't be simpler.

### Less code more better

Writing code is hard, writing useful code is even harder, but writing no code is genius. **silly** is meant to contain no useless code.

### Just a test runner, nothing more

You won't find anything besides the test runner here. It's not test runner's business to provide you with assertions and other nonsense.

### Don't reinvent the wheel

[dub](https://dub.pm/) is a great tool and there's no reason not to use it. Some other test runners use scripts or even integrate dub as part of them but **silly** is just an another dependency of your project.

### It just works

Just add it as a dependency and that's it. No editing of your project's source code is required. No editing of `dub.json/dub.sdl` except for adding a dependency is required. No changes in your editor config or terminal aliases are required, **silly** just runs with
```
$ dub test
```

### Your choice, your test runner

It's up to you whether you want to use this test runner or not. Get rid of it just by removing the dependency. It won't break your CI/CD scripts and cause any trouble.

## Installation

Just add **silly** as a dependency of your project and that's it.

### dub.json

```json
{
	<...>
	"dependencies": {
		"silly": "~>0.0.1"
	}
}
```

### dub.sdl

```
<...>
dependency "silly" version="~>0.0.1"
```
