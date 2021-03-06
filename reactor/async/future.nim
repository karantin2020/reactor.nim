## A `Future` represents the result of an asynchronous computation. `Completer` is used to create and complete Futures - it can be thought as of an other side of a Future.

type
  Future*[T] = object
    case isImmediate: bool
    of true:
      value: T
    of false:
      completer: Completer[T]

  CompleterNil[T] = ref object of RootObj
    when debugFutures:
      stackTrace: string

    consumed: bool

    case isFinished: bool
    of true:
      result: Result[T]
    of false:
      data: RootRef
      callback: (proc(data: RootRef, future: Completer[T]) {.closure.})

  Completer*[T] = CompleterNil[T]

  Bottom* = object

proc makeInfo[T](f: Future[T]): string =
  if f.isImmediate:
    return "immediate"
  else:
    let c = f.completer
    result = ""
    if c.isFinished:
      if c.consumed:
        result &= "consumed "
      result &= $c.result
    else:
      result &= "unfinished"

proc `$`*[T](c: Future[T]): string =
  "Future " & makeInfo(c)

proc `$`*[T](c: Completer[T]): string =
  "Completer " & makeInfo(c.getFuture)

proc getFuture*[T](c: Completer[T]): Future[T] =
  ## Retrieves a Future managed by the Completer.
  Future[T](isImmediate: false, completer: c)

proc destroyCompleter[T](f: Completer[T]) =
  if not f.consumed:
    stderr.writeLine "Destroyed unconsumed future ", $f.getFuture
    when debugFutures:
      stderr.writeLine f.stackTrace

proc newCompleter*[T](): Completer[T] =
  ## Creates a new completer.
  new(result, destroyCompleter[T])
  result.isFinished = false
  when debugFutures:
    result.stackTrace = getStackTrace()

proc now*[T](res: Result[T]): Future[T] =
  ## Returns already completed Future containing result `res`.
  if res.isSuccess:
    when T is void:
      return Future[T](isImmediate: true)
    else:
      return Future[T](isImmediate: true, value: res.value)
  else:
    return Future[T](isImmediate: false, completer: Completer[T](isFinished: true, result: res))

proc immediateFuture*[T](value: T): Future[T] {.deprecated.} =
  let r = just(value)
  return now(r)

proc immediateFuture*(): Future[void] {.deprecated.} =
  now(just())

proc immediateError*[T](value: string): Future[T] {.deprecated.} =
  now(error(T, value))

proc immediateError*[T](value: ref Exception): Future[T] {.deprecated.} =
  now(error(T, value))

proc isCompleted*(self: Future): bool =
  ## Checks if a Future is completed.
  return self.isImmediate or self.completer.isFinished

proc isSuccess*(self: Future): bool =
  ## Checks if a Future is completed and doesn't contain an error.
  return self.isImmediate or (self.completer.isFinished and self.completer.result.isSuccess)

proc getResult*[T](self: Future[T]): Result[T] =
  ## Returns the result represented by a completed Future.
  if self.isImmediate:
    when T is not void:
      return just(self.value)
    else:
      return just()
  else:
    assert self.completer.isFinished
    self.completer.consumed = true
    return self.completer.result

proc get*[T](self: Future[T]): T =
  ## Returns the value represented by a completed Future.
  ## If the Future contains an error, raise it as an exception.
  if self.isImmediate:
    when T is not void:
      return self.value
  else:
    assert self.completer.isFinished
    self.completer.consumed = true
    when T is void:
      self.completer.result.get
    else:
      return self.completer.result.get

proc completeResult*[T](self: Completer[T], x: Result[T]) =
  ## Complete a Future managed by the Completer with result `x`.
  assert (not self.isFinished)
  let data = self.data
  let callback = self.callback
  self.data = nil
  self.callback = nil
  self.isFinished = true
  self.result = x
  if callback != nil:
    callback(data, self)

proc complete*[T](self: Completer[T], x: T) =
  ## Complete a Future managed by the Completer with value `x`.
  self.completeResult(just(x))

proc complete*(self: Completer[void]) =
  ## Complete a void Future managed by the Completer.
  completeResult[void](self, just())

proc completeError*[T](self: Completer[T], x: ref Exception) =
  ## Complete a Future managed by the Completer with error `x`.
  self.completeResult(error(T, x))

proc onSuccessOrError*[T](f: Future[T], onSuccess: (proc(t:T)), onError: (proc(t:ref Exception))) =
  ## Call `onSuccess` or `onError` when Future is completed. If Future is already completed, one of these functions is called immediately.
  if f.isImmediate:
    when T is void:
      onSuccess()
    else:
      onSuccess(f.value)
    return

  let c = f.completer
  c.consumed = true
  if c.isFinished:
    onSuccessOrErrorR[T](c.result, onSuccess, onError)
  else:
    c.callback =
      proc(data: RootRef, compl: Completer[T]) =
        onSuccessOrError[T](f, onSuccess, onError)

proc onSuccessOrError*(f: Future[void], onSuccess: (proc()), onError: (proc(t:ref Exception))) =
  onSuccessOrError[void](f, onSuccess, onError)

proc onError*(f: Future[Bottom], onError: (proc(t: ref Exception))) =
  onSuccessOrError(f, nil, onError)

proc ignoreResult*[T](f: Future[T]): Future[Bottom] =
  let completer = newCompleter[Bottom]()

  onSuccessOrError[T](f, onSuccess=nothing1[T],
                      onError=proc(t: ref Exception) = completeError(completer, t))

  return completer.getFuture

proc ignoreError*[Exc](f: Future[void], kind: typedesc[Exc]): Future[void] =
  ## Ignore an error in Future `f` of kind `kind` and transform it into successful completion.
  let completer = newCompleter[void]()

  onSuccessOrError[void](f, onSuccess=(proc() = complete(completer)),
                         onError=proc(t: ref Exception) =
                                if t.getOriginal of Exc: complete(completer)
                                else: completer.completeError(t))

  return completer.getFuture

converter ignoreVoidResult*(f: Future[void]): Future[Bottom] {.deprecated.} =
  ignoreResult(f)

proc thenNowImpl[T, R](f: Future[T], function: (proc(t:T):R)): auto =
  let completer = newCompleter[R]()

  proc onSuccess(t: T) =
    when R is void:
      when T is void:
        function()
      else:
        function(t)
      complete[R](completer)
    else:
      when T is void:
        complete[R](completer, function())
      else:
        complete[R](completer, function(t))

  onSuccessOrError[T](f, onSuccess=onSuccess,
                      onError=proc(t: ref Exception) = completeError[R](completer, t))

  return completer.getFuture

proc completeFrom*[T](c: Completer[T], f: Future[T]) =
  ## When Future `f` completes, complete the Future managed by `c` with the same result.
  onSuccessOrError[T](f,
                      onSuccess=proc(t: T) =
                        when T is void: complete[T](c)
                        else: complete[T](c, t),
                      onError=proc(t: ref Exception) = completeError[T](c, t))

proc thenChainImpl[T, R](f: Future[T], function: (proc(t:T): Future[R])): Future[R] =
  let completer = newCompleter[R]()

  proc onSuccess(t: T) =
    when T is void:
      var newFut = function()
    else:
      var newFut = function(t)
    completeFrom[R](completer, newFut)

  onSuccessOrError[T](f, onSuccess=onSuccess,
                      onError=proc(t: ref Exception) = completeError[R](completer, t))

  return completer.getFuture

proc declval[R](r: typedesc[R]): R =
  raise newException(Exception, "executing declval")

proc thenWrapper[T, R](f: Future[T], function: (proc(t:T):R)): auto =
  when R is Future:
    when R is Future[void]:
      return thenChainImpl[T, void](f, function)
    else:
      return thenChainImpl[T, type(declval(R).value)](f, function)
  else:
    return thenNowImpl[T, R](f, function)

proc then*[T](f: Future[void], function: (proc(): T)): auto =
  return thenWrapper[void, T](f, function)

proc then*[T](f: Future[T], function: (proc(t:T))): auto =
  return thenWrapper[T, void](f, function)

proc then*(f: Future[void], function: (proc())): auto =
  return thenWrapper[void, void](f, function)

proc then*[T, R](f: Future[T], function: (proc(t:T): R)): auto =
  return thenWrapper[T, R](f, function)

proc ignoreFailCb(t: ref Exception) =
  stderr.writeLine("Error in ignored future")
  t.printError

proc ignore*(f: Future[void]) =
  ## Discard the future result.
  onSuccessOrError[void](f,
                         proc(t: void) = discard,
                         ignoreFailCb)

proc ignore*[T](f: Future[T]) =
  ## Discard the future result.
  f.onSuccessOrError(nothing1[T], ignoreFailCb)

proc completeError*(self: Completer, x: string) =
  self.completeError(newException(Exception, x))

proc waitForever*(): Future[void] =
  let completer = newCompleter[void]()
  return completer.getFuture

proc runLoop*[T](f: Future[T]): T =
  ## Run the event loop until Future `f` completes, return the value. If the Future completes with an error, raise it as an exception. Consider using `runMain` instead of this.
  var loopRunning = true

  if not f.isCompleted:
    f.completer.callback = proc(data: RootRef, future: Completer[T]) = stopLoop()

  while not f.isCompleted:
    if not loopRunning:
      raise newException(Exception, "loop finished, but future is still uncompleted")
    loopRunning = runLoopOnce()

  f.get

proc runMain*(f: Future[void]) =
  ## Run the event loop until Future `f` completes, return the value. If the Future completes with an error, print pretty stack trace and quit.
  try:
    f.runLoop
  except:
    getCurrentException().printError
    quit(1)
