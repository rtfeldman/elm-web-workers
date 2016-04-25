**CAUTION: NOWHERE NEAR READY FOR PRODUCTION USE!** This is barely at the proof-of-concept at this point!

# elm-web-workers

Write Elm code that talks to Web Workers.

Design goals:

* You can write Elm code that does Web Worker stuff using a supervisor/worker pattern suggested by [**@evancz**](https://github.com/evancz)
* Your code will not only work in a browser, but will also work on Node as long as you have [webworker-threads](https://www.npmjs.com/package/webworker-threads) installed.

Implementation notes:

* End user will have to write some ports and some js (that calls out to the npm library) to kick everything off.
* Don't assume `require` is available; that means all third-party dependencies must be optional.

You can try out the example with:

```bash
$ cd examples
$ npm install .. && npm run example
```

It claims it's running a bunch of workers. They aren't doing anything CPU-intensive,
so you sort of have to take its word for it. A really stunning demo, I know.
