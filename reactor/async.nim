import future
import tables, hashes, strutils

export future.`=>`, future.`->`

import reactor/util
import reactor/datatypes/queue
import reactor/datatypes/basic
import reactor/loop

const debugFutures = not defined(release)

include reactor/async/event
include reactor/async/result
include reactor/async/future
include reactor/async/stream
include reactor/async/asyncmacro
include reactor/async/bytes
include reactor/async/asyncutil

import reactor/datatypes/basic
export ConstView, View, ByteView, viewToConstView, seqView, basic.len, singleItemView, copyTo, copyFrom, addrView, slice

when not compileOption("boundChecks"):
  {.warning: "compiling without boundChecks is dangerous and unsupported".}

when not compileOption("fieldChecks"):
  {.warning: "compiling without fieldChecks is dangerous and unsupported".}

when not compileOption("objChecks"):
  {.warning: "compiling without objChecks is dangerous and unsupported".}
