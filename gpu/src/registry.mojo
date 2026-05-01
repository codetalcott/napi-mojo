## gpu/src/registry.mojo — process-lifetime handle registry for GPU resources
##
## Why a registry instead of N-API GC handles: Mojo 1.0.0b1 doesn't expose
## a way to obtain a thin C-ABI function pointer from a `def`, so any
## address-of-a-Mojo-finalizer extraction yields a sentinel that crashes
## when N-API actually invokes it (consistently on Linux, intermittently
## on macOS). We avoid that whole code path by storing GPU resources in a
## process-lifetime registry keyed by a UInt64 id and returning the id to
## JS as a BigInt handle. freeMatrix removes the entry and releases the
## device buffer synchronously — no GC finalizers anywhere.
##
## Concurrency: single-threaded for now (all access from JS main thread).
## Add a mutex when matmul's worker-thread execute callback needs to read.

from std.memory import alloc
from std.gpu.host import DeviceBuffer


comptime DTYPE = DType.float32

# Cap on live handles. Bumping is just an alloc[...](N) change.
comptime MAX_HANDLES: Int = 1024


## Payload for one occupied slot. Move-only because DeviceBuffer is.
struct MatrixSlotData(Movable):
    var id: UInt64
    var dev_data: DeviceBuffer[DTYPE]
    var rows: Int
    var cols: Int

    def __init__(
        out self,
        id: UInt64,
        var dev_data: DeviceBuffer[DTYPE],
        rows: Int,
        cols: Int,
    ):
        self.id = id
        self.dev_data = dev_data^
        self.rows = rows
        self.cols = cols

    def __moveinit__(out self, deinit take: Self):
        self.id = take.id
        self.dev_data = take.dev_data^
        self.rows = take.rows
        self.cols = take.cols


## MatrixRegistry — owns the slot array.
##
## Slot value is `Optional[MatrixSlotData]`; None == free slot. Ids never
## get reused: the counter only increments, so a freed handle's id can't
## be confused with a fresh allocation.
struct MatrixRegistry(Movable):
    var slots: UnsafePointer[Optional[MatrixSlotData], MutAnyOrigin]
    var capacity: Int
    var next_id: UInt64

    def __init__(out self):
        self.slots = alloc[Optional[MatrixSlotData]](MAX_HANDLES)
        for i in range(MAX_HANDLES):
            (self.slots + i).init_pointee_move(
                Optional[MatrixSlotData](None)
            )
        self.capacity = MAX_HANDLES
        self.next_id = 1  # 0 reserved as "invalid handle" sentinel

    def __moveinit__(out self, deinit take: Self):
        self.slots = take.slots
        self.capacity = take.capacity
        self.next_id = take.next_id

    ## insert — claim a free slot, return the new id. Caller transfers
    ## ownership of `dev_data` into the registry.
    def insert(
        mut self,
        var dev_data: DeviceBuffer[DTYPE],
        rows: Int,
        cols: Int,
    ) raises -> UInt64:
        for i in range(self.capacity):
            var slot = self.slots + i
            if slot[] is None:
                var id = self.next_id
                self.next_id += 1
                slot[] = Optional[MatrixSlotData](
                    MatrixSlotData(id, dev_data^, rows, cols)
                )
                return id
        raise Error(
            "MatrixRegistry: capacity exceeded (max "
            + String(MAX_HANDLES)
            + " live handles)"
        )

    ## get — locate a slot by id. None if unknown or already freed.
    def get(self, id: UInt64) -> Optional[Int]:
        if id == 0:
            return Optional[Int](None)
        for i in range(self.capacity):
            var slot = self.slots + i
            if slot[] is not None:
                if slot[].value().id == id:
                    return Optional[Int](i)
        return Optional[Int](None)

    ## remove — free the slot. Idempotent on unknown ids.
    def remove(mut self, id: UInt64) -> Bool:
        if id == 0:
            return False
        for i in range(self.capacity):
            var slot = self.slots + i
            if slot[] is not None:
                if slot[].value().id == id:
                    slot[] = Optional[MatrixSlotData](None)
                    return True
        return False

    ## live_count — how many slots are currently occupied. O(n).
    def live_count(self) -> Int:
        var count = 0
        for i in range(self.capacity):
            if (self.slots + i)[] is not None:
                count += 1
        return count

    ## remove_all — free every occupied slot. Used by freeAll().
    def remove_all(mut self):
        for i in range(self.capacity):
            var slot = self.slots + i
            if slot[] is not None:
                slot[] = Optional[MatrixSlotData](None)
