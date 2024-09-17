# proximity-sort

Zig implementation of [@jonhoo][jon-gjengset]'s [proximity-sort][proximity-sort].

## Why?

I just started learning Zig. And, proximity-sort felt like a good first project.

## Overview

The command-line utility sorts the inputs (from stdin) by their path proximity (number of shared leading path components) to a given path.

## Example Usage

```shell
fd -t f | zig-out/bin/proximity-sort /path/to/file | fzf --reverse --tiebreak=index
```

## Building from Source

If you have [zig master](https://ziglang.org/download/) installed, you can build this with -

```shell
zig build -Doptimize=ReleaseSafe
```

## Credits & References

-   [proximity-sort][proximity-sort] by [@jonhoo][jon-gjengset]
-   [Performance Optimizer Observation Platform][performance-optimizer-observation-platform] by [@andrewrk][andrew-kelley].

[jon-gjengset]: https://github.com/jonhoo/
[andrew-kelley]: https://github.com/andrewrk/
[proximity-sort]: https://github.com/jonhoo/proximity-sort/
[performance-optimizer-observation-platform]: https://github.com/andrewrk/poop/
