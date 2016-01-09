import macros

type
  AsyncIterator* = object
    callback: proc(cont: proc())

proc iterFuture[T](f: Future[T]): AsyncIterator =
  let completer = f.completer
  result.callback = proc(cont: proc()) =
    completer.callback = proc(data: RootRef, future: Completer[T]) =
      cont()

template awaitInIterator*(body: expr): expr =
  let fut = body
  if not fut.isCompleted:
    yield iterFuture(fut)
  if not (fut.isImmediate or fut.completer.isSuccess):
    asyncProcCompleter.completeError(fut.completer.error)
    yield AsyncIterator(callback: nil) # we will never be called again

  when not (fut is Future[void]):
    fut.get

template await*(body): expr =
  {.error: "await outside of an async proc".}
  discard

proc asyncIteratorRun*(it: (iterator(): AsyncIterator)) =
  var asyncIter = it()
  if finished(it):
    return
  if asyncIter.callback != nil:
    asyncIter.callback(proc() = asyncIteratorRun(it))

macro async*(a): stmt =
  ## `async` macro. Enables you to write asynchronous code in a similar manner to synchronous code.
  ##
  ## For example:
  ## ```
  ## proc add5(s: Future[int]): Future[int] {.async.} =
  ##   asyncReturn((await s) + 5)
  ## ```

  let procName = a[0]
  let params = if a[3].len > 1: a[3][1] else: nil
  let pragmas = a[4]
  let body = a[6]
  let returnTypeFull = a[3][0]

  if returnTypeFull.kind != nnkEmpty and (returnTypeFull.kind != nnkBracketExpr or returnTypeFull[0] != newIdentNode(!"Future")):
    error("invalid return type from async proc (expected Future[T])")

  let returnType = if returnTypeFull.kind == nnkEmpty: newIdentNode(!"void")
                   else: returnTypeFull[1]
  let returnTypeNew = newNimNode(nnkBracketExpr)
  returnTypeNew.add newIdentNode(!"Future")
  returnTypeNew.add returnType

  let asyncHeader = parseStmt("""
template await(e: expr): expr = awaitInIterator(e)
template asyncRaise(e: expr): expr =
  asyncProcCompleter.completeError(e)
  return
template asyncReturn(e: expr): expr =
  asyncProcCompleter.complete(e)
  return""")

  let asyncFooter = parseStmt("""
asyncIteratorRun(iter)
return asyncProcCompleter.getFuture""")

  let headerNext = parseStmt("let asyncProcCompleter = newCompleter[int]()")[0]
  headerNext[0][2][0][1] = returnType
  asyncHeader.add headerNext

  var asyncBodyTxt = """let iter = iterator(): AsyncIterator {.closure.} =
    discard
    """
  if returnType == newIdentNode(!"void"):
    asyncBodyTxt &= "asyncProcCompleter.complete()"
  else:
    asyncBodyTxt &= "asyncProcCompleter.completeError(\"missing asyncReturn\")"
  let asyncBody = parseStmt(asyncBodyTxt)[0]

  asyncBody[0][2][6] = body

  asyncHeader.add(asyncBody)
  asyncHeader.add(asyncFooter)

  result = newProc(procName)
  result[3] = newNimNode(nnkFormalParams)
  result[3].add returnTypeNew
  if params != nil:
    result[3].add params
  result[4] = pragmas
  result[6] = asyncHeader

macro asyncFor*(iterClause: expr, body: expr): stmt =
  ## An asynchronous version of `for` that works on Streams. Example:
  ## ```
  ## proc simplePipe(src: Stream[int], dst: Provider[int]) {.async.} =
  ##   asyncFor item in src:
  ##     echo "piping ", item
  ##     await dst.provide(item)
  ## ```