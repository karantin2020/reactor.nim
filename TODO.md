### FIXME
* async procs may cause stack overflow in some situations
* queue chunk size is always 4096
* JustClose in i.e. receiveAll should be chaned to EofError
* `return` in async without value in nonvoid proc crashes compiler
* queues with objects keep too much alive (should reset to nil)
* URLs without trailing slash in httpclient

### TODO
* optimize `then` for immediate futures
* add variant of `map` for function returning `Future`s
* `TaskQueue` for cancellation and concurrency limitation
* show all currently running coroutines
* Future should be non nil or something
* httpclient connection pool support
* stdlib asyncdispatch compat
* Redis: autoreconnect

### TODO (asyncmacro)
* `yield` to `asyncYield`
* add try-except support
* (possibly) catch all other exceptions and convert to async failure
* rewriting of returns inside asyncReturn
* make defer work
