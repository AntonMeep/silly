silly
=====

**silly** is a no-nonsense test runner for the D programming language. Instead of re-inventing the wheel and adding more and more levels of abstraction it just works, requiring as little effort from the programmer as possible.

## Why?

Built-in unittest runner is not good enough. It does its job, but it doesn't show what tests were executed. It just runs them all stopping on the first failed one. Of course, community offers many different solutions for that problem, from small little tools for hobbyists to humongous frameworks. Still, these are either not good enough or *too* good.

**silly** is developed with strict principles in mind.

### Keep It Simple, Silly

Just a general rule to not make things hard where it isn't necessary and eliminate places where it is necessary. 

### Less code more better

Writing code is hard, writing useful code is even harder, but writing no code is genius. **silly** is meant to contain no useless code.

### Just a test runner, nothing more

You won't find anything besides the test runner here. It's not test runner's business to provide you with assertions and other nonsense.

### Don't reinvent the wheel

[dub](https://dub.pm/) is a great tool and there's no reason not to use it. Some other test runners use scripts or even integrate dub as part of them but **silly** is just an another dependency of your project.

### It just works

Just add it as a dependency and that's it. No editing of your project's source code is required. No editing of `dub.json/dub.sdl` besides adding a dependency is required. No changes in your editor config or terminal aliases are required, **silly** just runs with
```
$ dub test
```

### Your choice, your test runner

It's up to you whether you want to use this test runner or not. Get rid of it just by removing the dependency.

### Just for unit tests

`unittest` blocks in D are meant (obviously) for unit testing. If somebody uses them for any other purposes like integration testing then they're doing it wrong and **silly** won't be helpful for these people. 

## Installation

Just add **silly** as a dependency of your project and that's it.

## Advanced configuration

There's `debug` configuration that can be used to show additional information during compilation.
