**CAUTION: NOWHERE NEAR READY FOR PRODUCTION USE!** This is barely at the proof-of-concept at this point!

# elm-web-workers

Write Elm code that talks to Web Workers.

Design goals:

* You can write sane Elm code that does multithreaded Web Worker stuff
* Your code will not only work in a browser, but will also work on Node as long as you have [webworker-threads](https://www.npmjs.com/package/webworker-threads) installed.

You can try out the example with:

```bash
$ cd examples
$ npm install .. && npm run example
``

It claims it's running a bunch of workers. They aren't doing anything CPU-intensive,
so you sort of have to take its word for it. A really stunning demo, I know.
