
const debugFutures = not defined(release)

type
  FutureNil[T] = ref object
    when debugFutures:
      stackTrace: string

    case isFinished: bool
    of true:
      consumed: bool
      case isSuccess: bool
      of true:
        result: T
      of false:
        error: ref Exception
    of false:
      data: RootRef
      callback: (proc(data: RootRef, future: Future[T]) {.closure.})

  Future*[T] = FutureNil[T]

  CompleterNil {.borrow: `.`.}[T] = distinct FutureNil[T]

  Completer*[T] = CompleterNil[T]

  Bottom* = object

proc makeInfo[T](c: Future[T]): string =
  result = ""
  if c.isFinished:
    if c.consumed:
      result &= "consumed "
    if c.isSuccess:
      result &= "completed with success"
    else:
      result &= "completed with error"
  else:
    result &= "unfinished"

proc `$`*[T](c: Future[T]): string =
  "Future " & makeInfo(c)

proc `$`*[T](c: Completer[T]): string =
  "Completer " & makeInfo(c.getFuture)

proc getFuture*[T](c: Completer[T]): Future[T] =
  (Future[T])(c)

proc destroyFuture[T](f: Future[T]) =
  if not f.consumed:
    echo "Destroyed unconsumed future"
    when debugFutures:
      echo f.stackTrace

proc newCompleter*[T](): Completer[T] =
  var fut: Future[T]
  new(fut, destroyFuture[T])
  result = Completer[T](fut)
  result.getFuture.isFinished = false
  when debugFutures:
    result.getFuture.stackTrace = getStackTrace()

proc immediateFuture*[T](value: T): Future[T] =
  let self = newCompleter[T]()
  self.complete(value)
  return self.getFuture

proc immediateError*[T](value: string): Future[T] =
  let self = newCompleter[T]()
  self.completeError(value)
  return self.getFuture

proc immediateError*[T](value: ref Exception): Future[T] =
  let self = newCompleter[T]()
  self.completeError(value)
  return self.getFuture

proc complete*[T](self: Completer[T], x: T) =
  let self = self.getFuture
  assert (not self.isFinished)
  let data = self.data
  let callback = self.callback
  self.data = nil
  self.callback = nil
  self.isFinished = true
  self.isSuccess = true
  when T is not void:
    self.result = x
  if callback != nil:
    callback(data, self)

proc completeError*[T](self: Completer[T], x: ref Exception) =
  let self = self.getFuture
  assert (not self.isFinished)
  let data = self.data
  let callback = self.callback
  self.data = nil
  self.callback = nil
  self.isFinished = true
  self.isSuccess = false
  self.error = x
  if callback != nil:
    callback(data, self)

proc onSuccessOrError*[T](f: Future[T], onSuccess: (proc(t:T)), onError: (proc(t:ref Exception))) =
  if f.isFinished:
    f.consumed = true
    if f.isSuccess:
      when T is void:
        onSuccess()
      else:
        onSuccess(f.result)
    else:
      onError(f.error)
  else:
    f.callback =
      proc(data: RootRef, fut: Future[T]) =
        onSuccessOrError[T](f, onSuccess, onError)

proc thenNowImpl[T, R](f: Future[T], function: (proc(t:T):R)): auto =
  let completer = newCompleter[R]()

  proc onSuccess(t: T) =
    when R is void:
      function(t)
      complete[R](completer)
    else:
      complete[R](completer, function(t))

  onSuccessOrError[T](f, onSuccess=onSuccess,
                      onError=proc(t: ref Exception) = completeError[R](completer, t))

  return completer.getFuture

proc completeFrom*[T](c: Completer[T], f: Future[T]) =
  onSuccessOrError[T](f,
                      onSuccess=proc(t: T) = complete[T](c, t),
                      onError=proc(t: ref Exception) = completeError[T](c, t))

proc thenChainImpl[T, R](f: Future[T], function: (proc(t:T): Future[R])): Future[R] =
  let completer = newCompleter[R]()

  proc onSuccess(t: T) =
    var newFut = function(t)
    completeFrom[R](completer, newFut)

  onSuccessOrError[T](f, onSuccess=onSuccess,
                      onError=proc(t: ref Exception) = completeError[R](completer, t))

  return completer.getFuture

proc declval[R](r: typedesc[R]): R =
  raise newException(Exception, "executing declval")

proc thenWrapper[T, R](f: Future[T], function: (proc(t:T):R)): auto =
  when R is Future:
    return thenChainImpl[T, type(declval(R).result)](f, function)
  else:
    return thenNowImpl[T, R](f, function)

proc then*[T](f: Future[T], function: (proc(t:T))): auto =
  return thenWrapper[T, void](f, function)

proc then*[T, R](f: Future[T], function: (proc(t:T): R)): auto =
  return thenWrapper[T, R](f, function)

proc ignoreFailCb(t: ref Exception) =
  echo "Error in ignored future: " & t.msg

proc ignore*(f: Future[void]) =
  onSuccessOrError[void](f,
                         proc(t: void) = discard,
                         ignoreFailCb)

proc ignore*[T](f: Future[T]) =
  f.onSuccessOrError(nothing1[T], ignoreFailCb)

proc completeError*(self: Completer, x: string) =
  self.completeError(newException(Exception, x))

macro async*(a: expr): expr =
  discard