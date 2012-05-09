//
// Copyright (C) 2008 Intel Corporation
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

//
// Author: Michael Adler
//
// A generic cache class (n-way set associative) for caching data in BRAM.
// Classes building a cache must provide an interface class to the source
// data of type RL_SA_CACHE_SOURCE_DATA (defined below).  The cache
// takes a number of parameters: the address and data types, the number of
// sets and the number of ways within each set.
//
// The cache may either be write-back (the default) or write-through.  For
// write through caches it is the callers responsibility to do the write
// to backing storage.  This cache class merely skips setting of the dirty
// bit on writes in write-through mode.
//

// Library imports.

import FIFO::*;
import FIFOF::*;
import Vector::*;
import SpecialFIFOs::*;
import List::*;

// Project foundation imports.

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/fpga_components.bsh"


// ===================================================================
//
// PUBLIC DATA STRUCTURES
//
// ===================================================================

//
// Load response
//
typedef struct
{
    // Not all returned words are guaranteed, so they are protected by Maybe#().
    // The requested word is guaranteed valid.
    Vector#(nWordsPerLine, Maybe#(t_CACHE_WORD)) words;
    t_CACHE_ADDR addr;
    // Word index requested by read.
    Bit#(TLog#(nWordsPerLine)) reqWordIdx;
    t_CACHE_REF_INFO refInfo;
}
RL_SA_CACHE_LOAD_RESP#(type t_CACHE_ADDR,
                       type t_CACHE_WORD,
                       numeric type nWordsPerLine,
                       type t_CACHE_REF_INFO)
    deriving (Eq, Bits);


//
// Cache mode can set the write policy or completely disable hits in the cache.
// This is mostly useful for debugging.
//
typedef enum
{
    RL_SA_MODE_WRITE_BACK,
    RL_SA_MODE_WRITE_THROUGH,
    RL_SA_MODE_DISABLED0,
    RL_SA_MODE_DISABLED1
}
RL_SA_CACHE_MODE
    deriving (Eq, Bits);


//
// Set associative cache interface.  nTagExtraLowBits is used just for
// debugging.  This specified number of low bits are prepanded to cache
// tags so addresses match those seen in other modules.
//
// t_CACHE_REF_INFO is metadata associated with a reference.  Metadata is
// passed to the backing store for fills.  The metadata is not stored in
// the cache.
//
interface RL_SA_CACHE#(type t_CACHE_ADDR,
                       type t_CACHE_WORD,
                       numeric type nWordsPerLine,
                       type t_CACHE_REF_INFO);

    // Read up to a full line.  Read from backing store if not already cached.
    // The read response is guaranteed to return at least the requested
    // word in the line.  If more of the line is already available it will
    // be returned as well.
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_REF_INFO refInfo);

    method ActionValue#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_REF_INFO)) readResp();

    // Some clients need the address to route responses.  Having a peek method
    // for response addresses avoids extra buffering in these clients.
    method t_CACHE_ADDR peekRespAddr();

    // Predicate to test whether a read response is ready this cycle.
    method Bool readRespReady();
    

    // Write a word to a cache line.  Word index 0 corresponds to the
    // low bits of a cache line.
    method Action write(t_CACHE_ADDR addr,
                        t_CACHE_WORD val,
                        Bit#(TLog#(nWordsPerLine)) wordIdx,
                        t_CACHE_REF_INFO refInfo);
    
    // Invalidate & flush requests.  Both write dirty lines back.  Invalidate drops
    // the line from the cache.  Flush keeps the line in the cache.  A response
    // is returned for invalOrFlushWait iff sendAck is true.
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck, t_CACHE_REF_INFO refInfo);
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck, t_CACHE_REF_INFO refInfo);
    method Action invalOrFlushWait();
    
    //
    // Set cache mode.  Mostly useful for debugging.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
    method Action setRecentLineCacheMode(Bool enabled);

    //
    // Debug scan state.  The cache can't instantiate a debug scan node because
    // the debug scan code depends on libRL.  Instantiating a node here would
    // create a source dependence loop.  Instead, a list of name/value pairs
    // is available for use by a client.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
    
    interface RL_CACHE_STATS stats;

endinterface: RL_SA_CACHE


//
// The caller must provide an instance of the RL_SA_CACHE_SOURCE_DATA interface
// so the cache can read and write data from the next level in the hierarchy.
//
// See RL_SA_CACHE interface for description of refInfo.
//
interface RL_SA_CACHE_SOURCE_DATA#(type t_CACHE_ADDR,
                                   type t_CACHE_LINE,
                                   numeric type nWordsPerLine,
                                   type t_CACHE_REF_INFO);

    // Read request and response with data
    method Action readReq(t_CACHE_ADDR addr, t_CACHE_REF_INFO refInfo);
    method ActionValue#(t_CACHE_LINE) readResp();
    
    // Asynchronous write (no response)
    method Action write(t_CACHE_ADDR addr,
                        Vector#(nWordsPerLine, Bool) wordValidMask,
                        t_CACHE_LINE val,
                        t_CACHE_REF_INFO refInfo);
    
    // Synchronous write.  writeSyncWait() blocks until the response arrives.
    method Action writeSyncReq(t_CACHE_ADDR addr,
                               Vector#(nWordsPerLine, Bool) wordValidMask,
                               t_CACHE_LINE val,
                               t_CACHE_REF_INFO refInfo);
    method Action writeSyncWait();

endinterface: RL_SA_CACHE_SOURCE_DATA

//
// Number of read ports required by the cache code.
typedef 3 RL_SA_CACHE_DATA_READ_PORTS;

//
// The caller must also provide storage for the cache's local data.  Local
// data includes both cache metadata and the cached values.
//
// A standard BRAM-based implementation of local data is provided in this
// module (mkBRAMCacheLocalData).
//
interface RL_SA_CACHE_LOCAL_DATA#(numeric type t_CACHE_ADDR_SZ,
                                  type t_CACHE_WORD,
                                  numeric type nWordsPerLine,
                                  numeric type nSets,
                                  numeric type nWays);

    //
    // Metadata access methods
    //
    interface MEMORY_IFC#(RL_SA_CACHE_SET_IDX#(nSets),
                          RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays)) metaData;
    
    //
    // Data access methods.  The methods are expected to merge the set and way
    // values into a linear address space.
    //
    method Action dataReadReq(Integer readPort,
                              RL_SA_CACHE_SET_IDX#(nSets) set,
                              RL_SA_CACHE_WAY_IDX#(nWays) way);

    method ActionValue#(Vector#(nWordsPerLine, t_CACHE_WORD)) dataReadRsp(Integer readPort);

    method Bool dataReadNotEmpty(Integer readPort);

    // Write up to an entire line, writing only the words with bits set in
    // wordMask.
    method Action dataWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_WAY_IDX#(nWays) way,
                            Vector#(nWordsPerLine, Bool) wordMask,
                            Vector#(nWordsPerLine, t_CACHE_WORD) val);

    // Write only a single word in a line.
    method Action dataWriteWord(RL_SA_CACHE_SET_IDX#(nSets) set,
                                RL_SA_CACHE_WAY_IDX#(nWays) way,
                                Bit#(TLog#(nWordsPerLine)) wordIdx,
                                t_CACHE_WORD val);
endinterface: RL_SA_CACHE_LOCAL_DATA


// ===================================================================
//
// PRIVATE DATA STRUCTURES
//
// ===================================================================

//
// Size of the conflicting reference holding queue.  Results may be returned
// out of order.  Only one request to a given line may be in flight.  Shunt
// conflicting requests to a side queue in order to allow other non-conflicting
// requests to proceed.
//
typedef 16 RL_SA_CONFLICTQ_ENTRIES;

//
// Data to be written to the cache.
//
typedef struct
{
    t_CACHE_WORD val;
}
RL_SA_CACHE_WRITE_INFO#(type t_CACHE_WORD, type t_CACHE_WRITE_WORD_IDX)
    deriving (Eq, Bits);

//
// Bit size of the write data heap index.  To save space, write data is passed
// through the cache pipelines as a pointer.  The heap size limits the number
// of writes in flight.  Writes never wait for a fill, so the heap doesn't
// have to be especially large.
//
typedef 3 WRITE_DATA_HEAP_IDX_SZ;

//
// Meta-data associated with a write request.
//
typedef struct
{
    Bit#(WRITE_DATA_HEAP_IDX_SZ) dataIdx;
    Bit#(TLog#(nWordsPerLine)) wordIdx;
}
RL_SA_CACHE_WRITE_REQ#(numeric type nWordsPerLine)
    deriving (Eq, Bits);


typedef UInt#(TLog#(nSets)) RL_SA_CACHE_SET_IDX#(numeric type nSets);
typedef UInt#(TLog#(nWays)) RL_SA_CACHE_WAY_IDX#(numeric type nWays);


//
// Cache way metadata (tag and a dirty bit). It is the responsibility of the
// package using this cache to drop insignificant low bits from the address
// size before addresses reach here.
//

typedef Bit#(TSub#(t_CACHE_ADDR_SZ, TLog#(nSets))) RL_SA_CACHE_TAG#(numeric type t_CACHE_ADDR_SZ, numeric type nSets);

typedef struct
{
    RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets) tag;
    Bool dirty;
    Vector#(nWordsPerLine, Bool) wordValid;
}
RL_SA_CACHE_WAY_METADATA#(numeric type t_CACHE_ADDR_SZ, numeric type nWordsPerLine, numeric type nSets)
    deriving(Bits, Eq);

//
// Cache set metadata includes LRU chain and the metadata for each way.  The
// way metadata is wrapped in a Maybe#() to permit invalid (unallocated) ways.
//
typedef struct
{
    Vector#(nWays, RL_SA_CACHE_WAY_IDX#(nWays)) lru;
    Vector#(nWays, Maybe#(RL_SA_CACHE_WAY_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets))) ways;
}
RL_SA_CACHE_SET_METADATA#(numeric type t_CACHE_ADDR_SZ, numeric type nWordsPerLine, numeric type nSets, numeric type nWays)
    deriving(Bits, Eq);

//
// The cache data is indexed by the set and the way within the set.
// Declaring the cache data as multiply indexed vectors results in a large
// amount of extra LUT usage to control the BRAMs.  Instead, we allocate a
// single large cache data BRAM and index it with a packed version of this
// structure:
//
typedef struct
{
    t_CACHE_SET_IDX set;
    RL_SA_CACHE_WAY_IDX#(nWays) way;
}
RL_SA_CACHE_DATA_IDX#(numeric type nWays, type t_CACHE_SET_IDX)
    deriving(Bits, Eq);


//
// Responses to flush and invalidate requests are returned in order to
// guarantee consistent state.  The number of entries in the scoreboard
// limits the number of requests in flight.
//
typedef 16 RL_SA_CACHE_MAX_INVAL;
typedef Bit#(TLog#(RL_SA_CACHE_MAX_INVAL)) RL_SA_CACHE_INVAL_IDX;


//
// Meta-data associated with a read request.
//
typedef struct
{
    Bit#(TLog#(nWordsPerLine)) wordIdx;
}
RL_SA_CACHE_READ_REQ#(numeric type nWordsPerLine)
    deriving (Eq, Bits);


//
// Basic request information constructed when a new request arrives.
//
// This declaration would be much cleaner if typedef could be inside a module
// after the types are known.
//
typedef struct
{
    t_CACHE_TAG     tag;
    t_CACHE_SET_IDX set;
    t_CACHE_WAY_IDX way;

    // Meta-data associated with the reference.  Meta-data has meaning only to the
    // caller.
    t_CACHE_REF_INFO refInfo;
}
RL_SA_CACHE_REQ_BASE#(type t_CACHE_TAG,
                      type t_CACHE_SET_IDX,
                      type t_CACHE_WAY_IDX,
                      type t_CACHE_REF_INFO)
    deriving(Bits, Eq);

typedef union tagged
{
    // Reads have no extra data (beyond RL_SA_CACHE_REQ_BASE above)
    RL_SA_CACHE_READ_REQ#(nWordsPerLine) HCOP_READ;

    // Writes have pointer to data to be written
    RL_SA_CACHE_WRITE_REQ#(nWordsPerLine) HCOP_WRITE;

    // Inval and flush have a bool indicating whether an ACK is needed
    Maybe#(RL_SA_CACHE_INVAL_IDX) HCOP_INVAL;
    Maybe#(RL_SA_CACHE_INVAL_IDX) HCOP_FLUSH_DIRTY;
}
RL_SA_CACHE_REQ#(numeric type nWordsPerLine)
    deriving(Bits, Eq);


// ========================================================================
//
// mkCacheSetAssoc --
//     Set associative cache.
//
//    NOTE: mkCacheSetAssoc may return read responses out of order relative
//          to the request order!  For in-order responses the caller
//          must add a tag to the t_CACHE_REF_INFO type and use the
//          tag to sort the responses.  A SCOREBOARD_FIFO would do the job.
//
// ========================================================================

module mkCacheSetAssoc#(RL_SA_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_CACHE_REF_INFO) sourceData,
                        RL_SA_CACHE_LOCAL_DATA#(t_CACHE_ADDR_SZ, t_CACHE_WORD, nWordsPerLine, nSets, nWays) localData,
                        NumTypeParam#(t_RECENT_READ_CACHE_IDX_SZ) param0,
                        NumTypeParam#(nTagExtraLowBits) param1,
                        DEBUG_FILE debugLog)
    // interface:
        (RL_SA_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_REF_INFO))
    provisos (Bits#(t_CACHE_LINE, t_CACHE_LINE_SZ),
              Bits#(t_CACHE_REF_INFO, t_CACHE_REF_INFO_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),

              // Write word size must tile into cache line
              Bits#(Vector#(nWordsPerLine, t_CACHE_WORD), t_CACHE_LINE_SZ),

              // Cache address size must be no larger than 128 bits because
              // of the hash function.
              Add#(t_CACHE_ADDR_SZ, a__, 128),

              // Set index and tag.  Set index size + tag size == address size.
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Bits#(t_CACHE_SET_IDX, t_CACHE_SET_IDX_SZ),
              Alias#(RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets), t_CACHE_TAG),

              // Set size must be no longer than 32 bits (for set filter)
              Add#(t_CACHE_SET_IDX_SZ, b__, 32),

              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              Alias#(RL_SA_CACHE_WAY_IDX#(nWays), t_CACHE_WAY_IDX),
              Alias#(RL_SA_CACHE_DATA_IDX#(nWays, t_CACHE_SET_IDX), t_CACHE_DATA_IDX),
              Alias#(RL_SA_CACHE_WAY_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets), t_METADATA),
              Alias#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_REF_INFO), t_CACHE_LOAD_RESP),
              Alias#(Vector#(nWays, RL_SA_CACHE_WAY_IDX#(nWays)), t_LRU_LIST),
              Alias#(Vector#(nWays, Maybe#(t_METADATA)), t_METADATA_VECTOR),
              Alias#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays), t_SET_METADATA),
              Alias#(RL_SA_CACHE_REQ_BASE#(t_CACHE_TAG, t_CACHE_SET_IDX, t_CACHE_WAY_IDX, t_CACHE_REF_INFO), t_CACHE_REQ_BASE),
              Alias#(RL_SA_CACHE_REQ#(nWordsPerLine), t_CACHE_REQ),
              Alias#(Bit#(TLog#(nWordsPerLine)), t_CACHE_WRITE_WORD_IDX),
              Alias#(RL_SA_CACHE_WRITE_INFO#(t_CACHE_WORD, t_CACHE_WRITE_WORD_IDX), t_CACHE_WRITE_INFO),
              Alias#(Vector#(nWordsPerLine, Bool), t_CACHE_WORD_VALID_MASK),
       
              Bits#(t_CACHE_REQ, t_CACHE_REQ_SZ),

              // Index and tag of local, recently read, line cache.
              Alias#(Bit#(t_RECENT_READ_CACHE_IDX_SZ), t_RECENT_READ_CACHE_IDX),
              Alias#(Bit#(TSub#(t_CACHE_ADDR_SZ, t_RECENT_READ_CACHE_IDX_SZ)), t_RECENT_READ_CACHE_TAG),
              Alias#(Maybe#(Tuple3#(t_RECENT_READ_CACHE_TAG,
                                    t_CACHE_LINE,
                                    t_CACHE_WORD_VALID_MASK)), t_RECENT_READ_CACHE_ENTRY),

              // Unbelievably ugly tautologies required by the compiler:
              Add#(TSub#(t_CACHE_ADDR_SZ, t_RECENT_READ_CACHE_IDX_SZ), t_RECENT_READ_CACHE_IDX_SZ, t_CACHE_ADDR_SZ),
              Add#(TSub#(t_CACHE_ADDR_SZ, TLog#(nSets)), TLog#(nSets), t_CACHE_ADDR_SZ),
              Add#(t_CACHE_ADDR_SZ, nTagExtraLowBits, TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)),
              Log#(nWays, TLog#(nWays)),
              Add#(TLog#(TExp#(TLog#(nSets))), 0, TLog#(nSets)),
              Add#(TLog#(TDiv#(TExp#(TLog#(nSets)), 2)), x__, TLog#(nSets)));

    // ***** Elaboration time checks of types"
    // The interface allows for a number of sets that isn't a
    // power of 2, but the implementation currently does not.
   
    if(valueof(nSets) != valueof(TExp#(TLog#(nSets))))
    begin
        error("nSets must be a power of 2");
    end
 


    // ***** Internal state *****

    Reg#(Bool) cacheIsEmpty <- mkReg(True);

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(Bit#(WRITE_DATA_HEAP_IDX_SZ), t_CACHE_WRITE_INFO) reqInfo_writeData <- mkMemoryHeapLUTRAM();

    // Is the cache write back?  If not, never set a dirty bit.  It is then the
    // responsibility of the caller to write values to backing storage.
    Reg#(RL_SA_CACHE_MODE) cacheMode <- mkReg(RL_SA_MODE_WRITE_BACK);
    function Bool writeBackCache() = (cacheMode == RL_SA_MODE_WRITE_BACK);
    function Bool cacheEnabled() = (pack(cacheMode)[1] == 0);

    // Filter for allowing one live operation per cache set.
    COUNTING_FILTER#(t_CACHE_SET_IDX, 1) setFilter <- mkCountingFilter(debugLog);

    // ***** Queues between internal pipeline stages *****

    // Incoming requests
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) newReqQ <- mkFIFOF();

    // First stage coming out of handleIncomingReq
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) processReqQ0 <- mkFIFOF();
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) processReqQ1 <- mkSizedFIFOF(8);

    // Hit path for operations that read the cache (read and flush)
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK)) readHitQ <- mkSizedFIFOF(8);

    // Queues on miss path
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_SET_METADATA)) lineMissQ <- mkFIFOF();
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK)) wordMissQ <- mkFIFOF();
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_METADATA)) evictDirtyForFillQ <- mkFIFOF1();

    // Fill for read path
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) fillLineRequestQ <- mkFIFOF();
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK)) fillLineQ <- mkSizedFIFOF(16);

    // Write data to an allocated queue entry
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, RL_SA_CACHE_WRITE_REQ#(nWordsPerLine))) writeDataQ <- mkFIFOF();

    // Wait for ACK from backing store that flush was received
    FIFO#(Tuple2#(t_CACHE_SET_IDX, Maybe#(RL_SA_CACHE_INVAL_IDX))) flushAckQ <- mkFIFO();

    // Exit from all paths
    FIFOF#(t_CACHE_SET_IDX) doneQ <- mkFIFOF();

    // Read responses may be returned out of order relative to request order!
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, RL_SA_CACHE_READ_REQ#(nWordsPerLine), t_CACHE_LINE, t_CACHE_WORD_VALID_MASK)) readRespToClientQ_OOO <- mkFIFOF();

    // Invalidate and flush requests are always returned in the order they
    // were requested.
    SCOREBOARD_FIFOF#(RL_SA_CACHE_MAX_INVAL, Bool) invalReqDoneQ <- mkScoreboardFIFOF();

    PulseWire readMissW          <- mkPulseWire();
    PulseWire writeMissW         <- mkPulseWire();
    PulseWire readHitW           <- mkPulseWire();
    PulseWire writeHitW          <- mkPulseWire();
    PulseWire invalEntryW        <- mkPulseWire();
    PulseWire forceInvalLineW    <- mkPulseWire();
    PulseWire dirtyEntryFlushW   <- mkPulseWire();
    PulseWire readRecentLineHitW <- mkPulseWire();


    // ***** Indexing functions *****

    //
    // getDataIdx --
    //     Index in the cache data BRAM given a set and way.
    //
    function t_CACHE_DATA_IDX getDataIdx (t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        t_CACHE_DATA_IDX idx;
        idx.set = set;
        idx.way = way;
        return idx;
    endfunction

    //
    // Functions for converting from address to tag and set or vice versa.
    //
    function Tuple2#(t_CACHE_TAG, t_CACHE_SET_IDX) cacheTagAndSet(t_CACHE_ADDR addr);
        return unpack(hashBits(addr));
    endfunction

    function t_CACHE_ADDR cacheAddr(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        t_CACHE_ADDR hashed_addr = { tag, pack(set) };
        return hashBits_inv(hashed_addr);
    endfunction

    //
    // debugAddr --
    //     Pretty printer for converting cache addresses to system addresses.
    //     Adds trailing 0's that were dropped from cache addresses because they
    //     are inside a cache line.
    //
    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddr(t_CACHE_ADDR addr);
        Bit#(nTagExtraLowBits) zero = 0;
        return { addr, zero };
    endfunction

    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddrFromTag(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        Bit#(nTagExtraLowBits) zero = 0;
        return { cacheAddr(tag, set), zero };
    endfunction


    // ***** Meta data searches *****

    function t_METADATA metaData(t_CACHE_TAG tag,
                                 Bool dirty,
                                 t_CACHE_WORD_VALID_MASK wordValid);
        t_METADATA meta;
        meta.tag = tag;
        meta.dirty = dirty;
        meta.wordValid = wordValid;
    
        return meta;
    endfunction


    function Maybe#(Tuple2#(t_CACHE_WAY_IDX, t_METADATA)) findWayMatch(t_CACHE_TAG tag, t_SET_METADATA meta);
        Vector#(nWays, Bool) way_match = replicate(False);

        for (Integer w = 0; w < valueOf(nWays); w = w + 1)
        begin
            way_match[w] = case (meta.ways[w]) matches
                               tagged Valid .m: (m.tag == tag);
                               default: False;
                           endcase;
        end

        let way = findElem(True, way_match);
        if (cacheEnabled() &&& way matches tagged Valid .w)
            return tagged Valid tuple2(w, validValue(meta.ways[w]));
        else
            return tagged Invalid;
    endfunction


    function Bool isInvalid(Maybe#(t) m) = ! isValid(m);


    function Maybe#(t_CACHE_WAY_IDX) findFirstInvalid(t_METADATA_VECTOR meta);
        return findIndex(isInvalid, meta);
    endfunction


    // ***** LRU Management ***** //

    //
    // getLRU --
    //   Least recently used way in a set.
    //
    function t_CACHE_WAY_IDX getLRU(t_LRU_LIST list);
        return list[valueOf(nWays) - 1];
    endfunction


    //
    // getMRU --
    //   Most recently used way in a set.
    //

    function t_CACHE_WAY_IDX getMRU(t_LRU_LIST list);
        return list[0];
    endfunction


    //
    // pushMRU --
    //   Update MRU list, moving a way to the head of the list.
    //
    function t_LRU_LIST pushMRU(t_LRU_LIST curLRU, t_CACHE_WAY_IDX mru);
        t_LRU_LIST new_list = curLRU;
    
        //
        // Find the new MRU value in the current list
        //
        if (findElem(mru, curLRU) matches tagged Valid .mru_pos)
        begin
            // mru_shift holds shifted MRU list.  The list is accurate from
            // position 0 to the old MRU position.
            let mru_shift = shiftInAt0(curLRU, mru);

            // Figure out which of the new mru_shift slots are needed.
            Bit#(nWays) mask = 0;
            mask[mru_pos] = 1;    // 1 in old MRU position
            mask = mask - 1;      // 1 in all slots lower than old MRU position
            mask[mru_pos] = 1;    // 1 in all slots up to and including old MRU position

            //
            // Shift older references out of the MRU slot
            //
            for (Integer w = 0; w < valueOf(nWays); w = w + 1)
            begin
                if (mask[w] == 1)
                    new_list[w] = mru_shift[w];
            end
        end

        return new_list;
    endfunction



    function ActionValue#(t_LRU_LIST) cacheLRUUpdate(t_CACHE_SET_IDX set,
                                                     t_CACHE_WAY_IDX way,
                                                     t_LRU_LIST cur_lru);
        actionvalue
        let new_lru = pushMRU(cur_lru, way);

        if ((getMRU(cur_lru) != way) || (cur_lru != new_lru))
        begin
            debugLog.record($format("    Update LRU (set=0x%x): %b -> %b", set, cur_lru, new_lru));
        end
        if (getMRU(new_lru) != way)
        begin
            debugLog.record($format("    ***ERROR*** expected MRU to be 0x%x but it is 0x%x", way, getMRU(new_lru)));
        end

        return new_lru;
        endactionvalue
    endfunction


    // ====================================================================
    //
    // Recent read line cache
    //
    // ====================================================================

    //
    // The recent line cache optimizes repeated reads to the same line
    // using a small BRAM cache.  This avoids the latency of reading meta data
    // and then the actual data.  Repeated references to the same line
    // occur because the L1 caches are word sized, not line sized.
    //

    // Recent line cache enabled?
    Reg#(Bool) enableRecentLineCache <- mkReg(True);

    MEMORY_IFC#(t_RECENT_READ_CACHE_IDX, t_RECENT_READ_CACHE_ENTRY)
        recentLineCache <- mkBRAMInitialized(tagged Invalid);

    // Lock out potential reads and writes of the same entry in a cycle
    RWire#(t_RECENT_READ_CACHE_IDX) recentLineWriteLock <- mkRWire();

    //
    // recentLineTagAndIdx --
    //   Indexing function for recent read cache.
    //
    function Tuple2#(t_RECENT_READ_CACHE_TAG,
                     t_RECENT_READ_CACHE_IDX) recentLineTagAndIdx(t_CACHE_TAG tag,
                                                                  t_CACHE_SET_IDX set);
        // Break cache address into recent read index and tag.
        return unpack({tag, pack(set)});
    endfunction

    function t_RECENT_READ_CACHE_TAG recentLineTag(t_CACHE_TAG tag,
                                                   t_CACHE_SET_IDX set) =
        tpl_1(recentLineTagAndIdx(tag, set));

    function t_RECENT_READ_CACHE_IDX recentLineIdx(t_CACHE_TAG tag,
                                                   t_CACHE_SET_IDX set) =
        tpl_2(recentLineTagAndIdx(tag, set));

    //
    // updateRecentReadLine --
    //   Write a new read value to the recent line cache.  Also sets the BRAM's
    //   write lock to avoid read and write of the same entry in an FPGA cycle.
    //
    function Action updateRecentReadLine(t_CACHE_TAG tag,
                                         t_CACHE_SET_IDX set,
                                         t_RECENT_READ_CACHE_ENTRY entry);
    action
        let idx = recentLineIdx(tag, set);
        recentLineCache.write(idx, entry);
        recentLineWriteLock.wset(idx);
    endaction
    endfunction

    //
    // Test whether a recent line is read-locked due to a write this cycle.
    // In some BRAM implementations, read and write of the same entry
    // produces unpredictable read results.
    //
    function Bool recentReadLineLocked(t_CACHE_TAG tag,
                                       t_CACHE_SET_IDX set);
        let recent_idx = recentLineIdx(tag, set);
        let recent_lock = recentLineWriteLock.wget();
        return (isValid(recent_lock) &&
                (recent_idx == validValue(recent_lock)));
    endfunction


    // ***** Rules ***** //

    // ====================================================================
    //
    // All incoming requests start here with handleIncomingReq
    //
    // ====================================================================

    //
    // Maintain a side buffer of requests to cache sets that already have
    // in-flight conflicting requests.  This allows non-conflicting requests
    // to proceed.
    //
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) sideReqQ <-
        mkSizedFIFOF(valueOf(RL_SA_CONFLICTQ_ENTRIES));

    // A very simple filter to detect lines with requests already in the side
    // cache.
    LUTRAM#(Bit#(6), Bit#(3)) sideReqFilter <- mkLUTRAM(0);
    Reg#(Bit#(2)) newReqArb <- mkReg(0);
    Wire#(Tuple2#(Bool, Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ))) curReq <- mkWire();

    (* fire_when_enabled, no_implicit_conditions *)
    rule incrReqArb (True);
        newReqArb <= newReqArb + 1;
    endrule

    //
    // pickReqQ --
    //     Decide whether to consider the new request or side request queue
    //     this cycle.  Filtering both is too expensive.
    //
    rule pickReqQueue (True);
        // New requests win over side requests if there is a new request
        // and the arbiter is non-zero.  If the arbitration counter newReqArb
        // is larger than 1 bit this favors new requests over side-buffer
        // requests in an effort to have as many requests in flight as possible.
        Bool pick_new_req = newReqQ.notEmpty &&
                            ((newReqArb != 0) || ! sideReqQ.notEmpty);

        let r = pick_new_req ? newReqQ.first() : sideReqQ.first();
        curReq <= tuple2(pick_new_req, r);
    endrule


    //
    // startReq --
    //     Start the current request if the line is not busy.
    //
    //     *** This rule could logically be merged with pickReqQueue above,
    //     *** but the Bluespec compiler chokes on the single rule version.
    //
    //     In order to preserve read/write and write/write order, the current
    //     request must either come from the side buffer or be a new request
    //     referencing a line not already in the side buffer.
    //
    //     The array sideReqFilter tracks lines active in the side request
    //     queue.
    //
    match {.curReq_pick_new_req, .curReq_r} = curReq;
    match {.curReq_req_base, .curReq_req} = curReq_r;

    (* fire_when_enabled *)
    rule startReq (! recentReadLineLocked(curReq_req_base.tag, curReq_req_base.set) &&&
                   (! curReq_pick_new_req ||
                    sideReqFilter.sub(resize(curReq_req_base.set)) == 0) &&&
                   setFilter.test(curReq_req_base.set) matches tagged Valid .filter_state);
        match {.pick_new_req, .r} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        setFilter.set(filter_state);

        // Not busy -- forward request...
        debugLog.record($format("  FWD %s to ReqQ: addr=0x%x, set=0x%x",
                                pick_new_req ? "new" : "side",
                                debugAddrFromTag(tag, set), set));

        // Read the current state of the recent line cache for the set.
        recentLineCache.readReq(recentLineIdx(tag, set));
        processReqQ0.enq(tuple2(req_base, req));

        if (pick_new_req)
        begin
            newReqQ.deq();
        end
        else
        begin
            sideReqQ.deq();
            sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) - 1);
        end
    endrule

    //
    // shuntNewReq --
    //     If the current request is new (not a shunted request) and the
    //     line is busy, shunt the new request to a side queue in order to
    //     attempt to process a later request that may be ready to go.
    //
    //     This rule will not fire if startReq fires.
    //
    (* descending_urgency = "startReq, shuntNewReq" *)
    rule shuntNewReq (! recentReadLineLocked(curReq_req_base.tag, curReq_req_base.set) &&
                      curReq_pick_new_req &&
                      (sideReqFilter.sub(resize(curReq_req_base.set)) != maxBound) &&
                      cacheEnabled);
        match {.pick_new_req, .r} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        // Line is busy.  Push request to side buffer so other requests
        // may flow around it.
        debugLog.record($format("  SIDE shunt req: addr=0x%x, set=0x%x",
                                debugAddrFromTag(tag, set), set));

        sideReqQ.enq(r);
        newReqQ.deq();

        // Note line present in sideReqQ
        sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) + 1);
    endrule


    //
    // handleIncomingReq1 --
    //     Second stage combines the request and the state of the recent
    //     line cache.  Now it can be known whether a meta data read is
    //     required.
    //
    rule handleIncomingReq1 (True);
        match {.req_base, .req} = processReqQ0.first();
        processReqQ0.deq();

        let recent_lc <- recentLineCache.readRsp();
        Bool recent_is_valid = isValid(recent_lc) && enableRecentLineCache;
        match {.recent_tag, .recent_line, .recent_word_valid_mask} = validValue(recent_lc);

        let tag = req_base.tag;
        let set = req_base.set;

        Bool recent_matches = recent_is_valid &&
                              (recent_tag == recentLineTag(tag, set));

        Bool early_exit = False;

        if (req matches tagged HCOP_READ .rReq)
        begin
            if (recent_matches && recent_word_valid_mask[rReq.wordIdx])
            begin
                // Recent line read hit!
                debugLog.record($format("  Read RECENT HIT: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, recent_word_valid_mask, recent_line));
                readRecentLineHitW.send();

                readRespToClientQ_OOO.enq(tuple4(req_base,
                                                 rReq,
                                                 recent_line,
                                                 recent_word_valid_mask));

                doneQ.enq(set);
                early_exit = True;
            end
        end
        else if (recent_matches)
        begin
            // Write to an entry stored in the recent line cache.  Simply invalidate
            // it instead of being clever.  Even if we were trying to be clever,
            // all we have is one word.
            debugLog.record($format("  RECENT Inval: addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
            updateRecentReadLine(tag, set, tagged Invalid);
        end

        if (! early_exit)
        begin
            //
            // Normal path -- no recent read line hit.
            //

            // Read meta data and LRU hints
            localData.metaData.readReq(req_base.set);

            processReqQ1.enq(tuple2(req_base, req));
        end
    endrule


    // ====================================================================
    //
    // Three stage path for invalidate or flush requests.  First stage
    // looks up the address in the cache.  If the line is present and dirty,
    // the second stage flushes it to the backing storage.  The third
    // stage responds with an ACK that storage is consistent, if requested.
    //
    // ====================================================================

    function Bool reqIsInvalOrFlush(t_CACHE_REQ req);
        if (req matches tagged HCOP_INVAL .needAck)
            return True;
        else if (req matches tagged HCOP_FLUSH_DIRTY .needAck)
            return True;
        else
            return False;
    endfunction

    //
    // handleInvalOrFlush --
    //     Invalidate and flush requests have similar handling.  Both write
    //     back a dirty matching line.  Flush preserves the now clean line
    //     in the cache.
    //
    (* conservative_implicit_conditions *)
    rule handleInvalOrFlush (reqIsInvalOrFlush(tpl_2(processReqQ1.first())));

        match {.req_base_in, .req} = processReqQ1.first();
        processReqQ1.deq();

        let meta <- localData.metaData.readRsp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        Maybe#(RL_SA_CACHE_INVAL_IDX) need_ack = ?;
        Bool is_inval = ?;

        case (req) matches
        tagged HCOP_INVAL .needACK:
        begin
            need_ack = needACK;
            is_inval = True;
            debugLog.record($format("  Process request: INVAL addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
        end
        tagged HCOP_FLUSH_DIRTY .needACK:
        begin
            need_ack = needACK;
            is_inval = False;
            debugLog.record($format("  Process request: FLUSH addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
        end
        endcase

        Bool found_dirty_line = False;
        let req_base_out = req_base_in;

        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            let meta_upd = meta;

            if (way_meta.dirty)
            begin
                // Found dirty line.  Prepare for write back.
                req_base_out.way = way;
                localData.dataReadReq(0, set, way);
                readHitQ.enq(tuple3(req_base_out, req, way_meta.wordValid));
                found_dirty_line = True;

                if (! is_inval)
                begin
                    // FLUSH:  Line no longer dirty.  Update meta data.
                    let new_meta = way_meta;
                    new_meta.dirty = False;
                    meta_upd.ways[way] = tagged Valid new_meta;
                end
            end

            if (is_inval)
            begin
                // Invalidate line
                meta_upd.ways[way] = tagged Invalid;
                forceInvalLineW.send();
            end

            localData.metaData.write(set, meta_upd);

            debugLog.record($format("  FLUSH/INVAL HIT %s: addr=0x%x, set=0x%x, way=%0d", (found_dirty_line ? "dirty" : "clean"), debugAddrFromTag(tag, set), set, way));
        end
        
        if (! found_dirty_line)
        begin
            // Line is not dirty.  Done with this request.
            doneQ.enq(set);
            if (need_ack matches tagged Valid .inval_idx)
                invalReqDoneQ.setValue(inval_idx, ?);
        end
    endrule


    //
    // flushDirtyLine --
    //   Flush a dirty line and continue on to fill, if appropriate.
    //
    rule flushDirtyLine (reqIsInvalOrFlush(tpl_2(readHitQ.first())));

        match {.req_base, .req, .word_valid_mask} = readHitQ.first();
        readHitQ.deq();

        let v <- localData.dataReadRsp(0);
        t_CACHE_LINE flush_data = unpack(pack(v));

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        Maybe#(RL_SA_CACHE_INVAL_IDX) need_ack =
            case (req) matches
                tagged HCOP_INVAL .needAck: needAck;
                tagged HCOP_FLUSH_DIRTY .needAck: needAck;
            endcase;

        dirtyEntryFlushW.send();
        debugLog.record($format("  Write back DIRTY: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, word_valid_mask, flush_data));

        // Flush for invalidate request.  Use sync method to know the
        // data arrived.
        sourceData.writeSyncReq(cacheAddr(tag, set), word_valid_mask, flush_data, req_base.refInfo);
        flushAckQ.enq(tuple2(set, need_ack));
    endrule


    //
    // handleFlushACK --
    //   Wait for the response to a flush from back storage for synchronous
    //   flushes.
    //
    rule handleFlushACK (True);
        sourceData.writeSyncWait();

        match { .set, .need_ack } = flushAckQ.first();
        flushAckQ.deq();

        // Done with this flush request.
        doneQ.enq(set);

        if (need_ack matches tagged Valid .inval_idx)
        begin
            invalReqDoneQ.setValue(inval_idx, ?);
            debugLog.record($format("  FLUSH or INVAL done, set=0x%x, invalIdx=%0d", set, inval_idx));
        end
        else
        begin
            debugLog.record($format("  FLUSH or INVAL done, set=0x%x", set));
        end
    endrule


    // ====================================================================
    //
    // Read and Write data path.
    //
    // ====================================================================

    //
    // handleRead --
    //     First unique stage of cache READ path.
    //
    (* conservative_implicit_conditions *)
    rule handleRead (tpl_2(processReqQ1.first()) matches tagged HCOP_READ .rReq);

        match {.req_base_in, .req} = processReqQ1.first();
        processReqQ1.deq();

        let meta <- localData.metaData.readRsp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        debugLog.record($format("  Process request: READ addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        let req_base_out = req_base_in;

        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            //
            // Line hit!
            //
            req_base_out.way = way;

            // Update LRU
            let meta_upd = meta;
            meta_upd.lru <- cacheLRUUpdate(set, way, meta.lru);

            if (way_meta.wordValid[rReq.wordIdx])
            begin
                // Word hit!
                readHitW.send();
                localData.dataReadReq(1, set, way);
                readHitQ.enq(tuple3(req_base_out, req, way_meta.wordValid));

                if (meta_upd.lru != meta.lru)
                begin
                    // LRU changed.  Update metadata.
                    localData.metaData.write(set, meta_upd);
                end
            end
            else
            begin
                // Line valid but word in line is not.  Fill.
                wordMissQ.enq(tuple3(req_base_out, req, way_meta.wordValid));

                // Mark all words valid in the line.  They will be after
                // the fill completes.
                meta_upd.ways[way] = tagged Valid metaData(tag, way_meta.dirty, replicate(True));

                localData.metaData.write(set, meta_upd);
            end
        end
        else
        begin
            // Miss.
            lineMissQ.enq(tuple3(req_base_out, req, meta));
        end
    endrule


    //
    // handleWrite --
    //     First unique stage of cache WRITE path.
    //
    (* conservative_implicit_conditions *)
    rule handleWrite (tpl_2(processReqQ1.first()) matches tagged HCOP_WRITE .wReq);

        match {.req_base_in, .req} = processReqQ1.first();
        processReqQ1.deq();

        let meta <- localData.metaData.readRsp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        debugLog.record($format("  Process request: WRITE addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        cacheIsEmpty <= False;
        let req_base_out = req_base_in;

        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            //
            // Line hit!
            //
            req_base_out.way = way;

            // Update LRU
            let meta_upd = meta;
            meta_upd.lru <- cacheLRUUpdate(set, way, meta.lru);

            writeHitW.send();

            // Mark line dirty and word valid
            let new_word_valid = way_meta.wordValid;
            new_word_valid[wReq.wordIdx] = True;

            meta_upd.ways[way] = tagged Valid metaData(tag, writeBackCache(), new_word_valid);

            // Update metadata if it is changed.  Skip the write otherwise, since
            // DDR writes are costly.
            if ((meta_upd.lru != meta.lru) ||
                (new_word_valid != way_meta.wordValid) ||
                ! way_meta.dirty)
            begin
                localData.metaData.write(set, meta_upd);
            end

            // Request write to cache
            writeDataQ.enq(tuple2(req_base_out, wReq));
            debugLog.record($format("  Write HIT: addr=0x%x, set=0x%x, way=%0d, mask=0x%x", debugAddrFromTag(tag, set), set, way, new_word_valid));
        end
        else
        begin
            // Miss.
            lineMissQ.enq(tuple3(req_base_out, req, meta));
        end
    endrule



    // ====================================================================
    //
    // Read or write hits end here.
    //
    // ====================================================================

    //
    // handleReadCacheHit --
    //   Forward data coming from cache BRAM from handleRead to back to the requester.
    //
    rule handleReadCacheHit (tpl_2(readHitQ.first()) matches tagged HCOP_READ .rReq);

        match {.req_base, .req, .word_valid_mask} = readHitQ.first();
        readHitQ.deq();

        let d <- localData.dataReadRsp(1);
        t_CACHE_LINE v = unpack(pack(d));

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        // Update the recent line cache
        updateRecentReadLine(tag, set,
                             tagged Valid tuple3(recentLineTag(tag, set),
                                                 v,
                                                 word_valid_mask));

        readRespToClientQ_OOO.enq(tuple4(req_base, rReq, v, word_valid_mask));

        // Done with this read request
        doneQ.enq(set);

        debugLog.record($format("  Read HIT: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, way, word_valid_mask, v));
    endrule


    //
    // writeCacheData --
    //   All cache writes terminate here, including the line miss path.
    //
    rule writeCacheData (True);
        match {.req_base, .w_req} = writeDataQ.first();
        writeDataQ.deq();

        let w_data = reqInfo_writeData.sub(w_req.dataIdx);

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        localData.dataWriteWord(set, way, w_req.wordIdx, w_data.val);

        debugLog.record($format("  WRITE Word: addr=0x%x, set=0x%x, way=%0d, word=%0d, data=0x%x", debugAddrFromTag(tag, set), set, way, w_req.wordIdx, w_data.val));

        if (! writeBackCache())
        begin
            // Send all writes to backing storage if in write-through mode.
            Vector#(nWordsPerLine, Bool) mask = replicate(False);
            mask[w_req.wordIdx] = True;
            Vector#(nWordsPerLine, t_CACHE_WORD) val = replicate(w_data.val);
            sourceData.write(cacheAddr(tag, set), mask, unpack(pack(val)), req_base.refInfo);
        end

        reqInfo_writeData.free(w_req.dataIdx);
        doneQ.enq(set);
    endrule


    // ====================================================================
    //
    // Miss handlers.
    //
    // ====================================================================

    //
    // handleWordMissForRead --
    //     Line is present in the cache but incomplete.  Request the full line
    //     from backing storage and merge it into the line.
    //
    rule handleWordMissForRead (tpl_2(wordMissQ.first()) matches tagged HCOP_READ .rReq);

        match {.req_base, .req, .word_valid_mask} = wordMissQ.first();
        wordMissQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;

        //
        // Miss.  Pick a victim.
        //

        readMissW.send();

        let addr = cacheAddr(tag, set);
        sourceData.readReq(addr, req_base.refInfo);
        fillLineQ.enq(tuple3(req_base, req, word_valid_mask));

        debugLog.record($format("  READ WORD MISS (FILL): addr=0x%x, set=0x%x, way=%0d", debugAddr(addr), set, req_base.way));
    endrule


    //
    // handleMissForRead --
    //     Pick a victim and prepare to fill a way from backing storage.
    //
    (* conservative_implicit_conditions *)
    rule handleMissForRead (tpl_2(lineMissQ.first()) matches tagged HCOP_READ .rReq);

        match {.req_base_in, .req, .meta} = lineMissQ.first();
        lineMissQ.deq();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        readMissW.send();

        //
        // Pick a fill victim:  either the first invalid or the LRU entry.
        // 
        t_CACHE_WAY_IDX fill_way = getLRU(meta.lru);
        if (findFirstInvalid(meta.ways) matches tagged Valid .inval_way)
        begin
            fill_way = inval_way;
        end

        let req_base_out = req_base_in;
        req_base_out.way = fill_way;

        // Update LRU
        let meta_upd = meta;
        meta_upd.lru <- cacheLRUUpdate(set, fill_way, meta.lru);

        //
        // Update metadata here for the filled line since we have the details.
        //
        meta_upd.ways[fill_way] = tagged Valid metaData(tag, False, replicate(True));
        localData.metaData.write(set, meta_upd);

        //
        // Now must figure out the next state...
        //

        // Is victim dirty?
        Bool flushed_dirty = False;
        if (meta.ways[fill_way] matches tagged Valid .m)
        begin
            invalEntryW.send();
            if (m.dirty)
            begin
                // Victim is dirty.  Flush data.
                flushed_dirty = True;
                localData.dataReadReq(2, set, fill_way);
                evictDirtyForFillQ.enq(tuple3(req_base_out, req, m));

                debugLog.record($format("  READ MISS (FLUSH): addr=0x%x, set=0x%x, way=%0d", debugAddrFromTag(m.tag, set), set, fill_way));
            end
        end

        if (! flushed_dirty)
        begin
            let addr = cacheAddr(tag, set);
            sourceData.readReq(addr, req_base_out.refInfo);
            fillLineQ.enq(tuple3(req_base_out, req, replicate(False)));

            debugLog.record($format("  READ MISS (FILL): addr=0x%x, set=0x%x, way=%0d", debugAddr(addr), set, req_base_out.way));
        end
    endrule


    //
    // handleMissForWrite --
    //     Pick a victim and write back the dirty data, if needed.
    //
    (* conservative_implicit_conditions *)
    rule handleMissForWrite (tpl_2(lineMissQ.first()) matches tagged HCOP_WRITE .wReq);

        match {.req_base_in, .req, .meta} = lineMissQ.first();
        lineMissQ.deq();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        writeMissW.send();

        //
        // Pick a fill victim:  either the first invalid or the LRU entry.
        // 
        t_CACHE_WAY_IDX fill_way = getLRU(meta.lru);
        if (findFirstInvalid(meta.ways) matches tagged Valid .inval_way)
        begin
            fill_way = inval_way;
        end

        let req_base_out = req_base_in;
        req_base_out.way = fill_way;

        // Update LRU
        let meta_upd = meta;
        meta_upd.lru <- cacheLRUUpdate(set, fill_way, meta.lru);

        //
        // Update metadata here for the filled line since we have the details.
        //
        
        // The full line will not be filled from memory for a write.  Only
        // mark the word being written valid.
        t_CACHE_WORD_VALID_MASK word_valid_mask = replicate(False);
        word_valid_mask[wReq.wordIdx] = True;

        // Update tag and write metadata
        meta_upd.ways[fill_way] = tagged Valid metaData(tag, writeBackCache(), word_valid_mask);
        localData.metaData.write(set, meta_upd);

        //
        // Now must figure out the next state...
        //

        // Is victim dirty?
        Bool flushed_dirty = False;
        if (meta.ways[fill_way] matches tagged Valid .m)
        begin
            invalEntryW.send();
            if (m.dirty)
            begin
                // Victim is dirty.  Flush data.
                flushed_dirty = True;
                localData.dataReadReq(2, set, fill_way);
                evictDirtyForFillQ.enq(tuple3(req_base_out, req, m));

                debugLog.record($format("  WRITE MISS (FLUSH): addr=0x%x, set=0x%x, way=%0d", debugAddrFromTag(m.tag, set), set, fill_way));
            end
        end

        if (! flushed_dirty)
        begin
            // Writing does not require a fill.  Ready now.
            writeDataQ.enq(tuple2(req_base_out, wReq));
            debugLog.record($format("  Write to INVAL: addr=0x%x, set=0x%x, way=%0d", debugAddr(cacheAddr(tag, set)), set, fill_way));
        end
    endrule


    //
    // evictDirtyForFill --
    //   Flush a dirty line and continue on to fill, if appropriate.
    //
    rule evictDirtyForFill (True);
        match {.req_base, .req, .flush_meta} = evictDirtyForFillQ.first();
        evictDirtyForFillQ.deq();

        let v <- localData.dataReadRsp(2);
        t_CACHE_LINE flush_data = unpack(pack(v));

        let set = req_base.set;
        let way = req_base.way;

        dirtyEntryFlushW.send();
        debugLog.record($format("  Write back DIRTY: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(flush_meta.tag, set), set, way, flush_meta.wordValid, flush_data));

        // Normal flush before a fill
        sourceData.write(cacheAddr(flush_meta.tag, set), flush_meta.wordValid, flush_data, req_base.refInfo);

        if (req matches tagged HCOP_WRITE .wReq)
        begin
            // WRITE: Line is empty and ready to receive write data.
            writeDataQ.enq(tuple2(req_base, wReq));
        end
        else
        begin
            // READ: Pass the request on to the fill stage.
            fillLineRequestQ.enq(tuple2(req_base, req));
        end
    endrule


    rule sendFillRequest (True);
        match {.req_base, .req} = fillLineRequestQ.first();
        fillLineRequestQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        let addr = cacheAddr(tag, set);
        sourceData.readReq(addr, req_base.refInfo);
        fillLineQ.enq(tuple3(req_base, req, replicate(False)));
    endrule


    //
    // handleFillForRead --
    //    Update the cache with requested data coming back from memory.
    //
    rule handleFillForRead (tpl_2(fillLineQ.first()) matches tagged HCOP_READ .rReq);

        match {.req_base, .req, .cur_word_valid_mask} = fillLineQ.first();
        fillLineQ.deq();

        let v <- sourceData.readResp();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        //
        // Cache the new values.  Don't overwrite entries that are currently
        // valid, since they may be dirty.
        //
        // On return only claim that the newly filled words are valid.
        // We could retrieve the entire line but that would take another
        // stage and more wires to read the dirty data from the cache.
        //
        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));
        localData.dataWrite(set, way, ret_valid_words, unpack(pack(v)));

        // Update the recent line cache
        updateRecentReadLine(tag, set,
                             tagged Valid tuple3(recentLineTag(tag, set),
                                                 v,
                                                 ret_valid_words));

        readRespToClientQ_OOO.enq(tuple4(req_base, rReq, v, ret_valid_words));
        debugLog.record($format("  Read FILL: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, way, ret_valid_words, v));

        doneQ.enq(set);
    endrule


    // ====================================================================
    //
    //   End of reference.
    //
    // ====================================================================

    // BE CAREFUL HERE!  Poor choice of order can cause deadlocks.
    (* descending_urgency = "writeCacheData, handleFlushACK, handleFillForRead, handleReadCacheHit, evictDirtyForFill, flushDirtyLine, sendFillRequest, handleWordMissForRead, handleMissForRead, handleMissForWrite, handleRead, handleWrite, handleInvalOrFlush, handleIncomingReq1" *)

    //
    // doneWithRef --
    //     All access paths terminate here.
    //
    rule doneWithRef (True);
        let set = doneQ.first();
        doneQ.deq();

        setFilter.remove(set);
    endrule


    // ====================================================================
    //
    //   Debug scan state
    //
    // ====================================================================

    List#(Tuple2#(String, Bool)) ds_data = List::nil;

    ds_data = List::cons(tuple2("SA Cache localData_MetaNotEmpty", localData.metaData.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache localData_Data0NotEmpty", localData.dataReadNotEmpty(0)), ds_data);
    ds_data = List::cons(tuple2("SA Cache localData_Data1NotEmpty", localData.dataReadNotEmpty(1)), ds_data);
    ds_data = List::cons(tuple2("SA Cache localData_Data2NotEmpty", localData.dataReadNotEmpty(2)), ds_data);

    ds_data = List::cons(tuple2("SA Cache writeDataQNotEmpty", writeDataQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache writeDataQNotFull", writeDataQ.notFull), ds_data);
    ds_data = List::cons(tuple2("SA Cache processReqQ0NotEmpty", processReqQ0.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache processReqQ1NotEmpty", processReqQ1.notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA Cache readHitQNotEmpty", readHitQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache lineMissQNotEmpty", lineMissQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache wordMissQNotEmpty", wordMissQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache evictDirtyForFillQNotEmpty", evictDirtyForFillQ.notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA Cache fillLineRequestQNotEmpty", fillLineRequestQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache newReqNotEmpty", newReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache fillLineQNotEmpty", fillLineQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA Cache doneQNotEmpty", doneQ.notEmpty), ds_data);

    let debugScanData = ds_data;


    // ====================================================================
    //
    //   Incoming cache requests (methods)
    //
    // ====================================================================

    //
    // genRequest --
    //     This function is used by most of the request methods to generate
    //     the internal data structure for managing a request.  It also starts
    //     the first step:  reading metadata from BRAM.
    //
    function ActionValue#(t_CACHE_SET_IDX) genRequest(t_CACHE_REQ req,
                                                      t_CACHE_ADDR addr,
                                                      t_CACHE_REF_INFO refInfo);
    actionvalue
        match {.tag, .set} = cacheTagAndSet(addr);

        t_CACHE_REQ_BASE req_base;
        req_base.tag = tag;
        req_base.set = set;
        req_base.way = ?;  // Way won't be known until the set meta data is read
        req_base.refInfo = refInfo;
        
        newReqQ.enq(tuple2(req_base, req));

        return set;
    endactionvalue
    endfunction


    //
    // readReq -- Read a full line.  Fetch from backing store if not in the cache.
    //
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_REF_INFO refInfo);

        RL_SA_CACHE_READ_REQ#(nWordsPerLine) req;
        req.wordIdx = wordIdx;
    
        let set <- genRequest(tagged HCOP_READ req, addr, refInfo);
        debugLog.record($format("  New request: READ addr=0x%x, set=0x%x, word=%0d", debugAddr(addr), set, wordIdx));
    endmethod

    method ActionValue#(t_CACHE_LOAD_RESP) readResp();
        match {.req_base, .r_req, .v, .valid_words} = readRespToClientQ_OOO.first();
        readRespToClientQ_OOO.deq();
        Vector#(nWordsPerLine, t_CACHE_WORD) value = unpack(pack(v));

        t_CACHE_LOAD_RESP rsp;
        for (Integer w = 0; w < valueOf(nWordsPerLine); w = w + 1)
            rsp.words[w] = valid_words[w] ? tagged Valid value[w] : tagged Invalid;
        rsp.addr = cacheAddr(req_base.tag, req_base.set);
        rsp.reqWordIdx = r_req.wordIdx;
        rsp.refInfo = req_base.refInfo;

        return rsp;
    endmethod

    method t_CACHE_ADDR peekRespAddr();
        match {.req_base, .r_req, .v, .valid_words} = readRespToClientQ_OOO.first();
        return cacheAddr(req_base.tag, req_base.set);
    endmethod

    method Bool readRespReady();
        return readRespToClientQ_OOO.notEmpty();
    endmethod

    //
    // write -- Write a word to a line.
    //
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_WRITE_WORD_IDX wordIdx, t_CACHE_REF_INFO refInfo);
        t_CACHE_WRITE_INFO w_info;
        w_info.val = val;

        let h <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(h, w_info);

        RL_SA_CACHE_WRITE_REQ#(nWordsPerLine) w_req;
        w_req.wordIdx = wordIdx;    
        w_req.dataIdx = h;

        let set <- genRequest(tagged HCOP_WRITE w_req, addr, refInfo);

        debugLog.record($format("  New request: WRITE addr=0x%x, set=0x%x, data=0x%x, word=%0d, wData heap=%0d", debugAddr(addr), set, val, wordIdx, h));
    endmethod


    //
    // invalReq -- Invalidate (remove) a line from the cache
    //
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck, t_CACHE_REF_INFO refInfo);
        if (sendAck)
        begin
            let idx <- invalReqDoneQ.enq();
            let set <- genRequest(tagged HCOP_INVAL tagged Valid idx, addr, refInfo);

            debugLog.record($format("  New request: INVAL addr=0x%x, set=0x%x, invalIdx=%d", debugAddr(addr), set, idx));
        end
        else
        begin
            let set <- genRequest(tagged HCOP_INVAL tagged Invalid, addr, refInfo);

            debugLog.record($format("  New request: INVAL addr=0x%x, set=0x%x", debugAddr(addr), set));
        end
    endmethod
    

    //
    // flushReq --
    //     Flush (write back) a line from the cache but keep the line cached.
    //
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck, t_CACHE_REF_INFO refInfo);
        if (sendAck)
        begin
            let idx <- invalReqDoneQ.enq();
            let set <- genRequest(tagged HCOP_FLUSH_DIRTY tagged Valid idx, addr, refInfo);

            debugLog.record($format("  New request: FLUSH addr=0x%x, set=0x%x, invalIdx=%d", debugAddr(addr), set, idx));
        end
        else
        begin
            let set <- genRequest(tagged HCOP_FLUSH_DIRTY tagged Invalid, addr, refInfo);

            debugLog.record($format("  New request: FLUSH addr=0x%x, set=0x%x", debugAddr(addr), set));
        end
    endmethod


    //
    // invalOrFlushWait -- Block until an inval or flush request completes.
    //
    method Action invalOrFlushWait();
        invalReqDoneQ.deq();
    endmethod


    //
    // setCacheMode -- Configure cache behavior.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
        if (cacheMode != mode)
            debugLog.record($format("Cache mode: %0d", mode));

        cacheMode <= mode;    
    endmethod


    //
    // setRecentLineCacheMode --
    //     Enable / disable recent line cache.
    //
    method Action setRecentLineCacheMode(Bool enabled);
        debugLog.record($format("Recent line cache: %s",
                                enabled ? "Enabled" : "Disabled"));

        enableRecentLineCache <= enabled;    
    endmethod


    //
    // debugScanState -- Return cache state for DEBUG_SCAN.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
        return debugScanData;
    endmethod

    interface RL_CACHE_STATS stats;
        method Bool readHit() = readHitW;
        method Bool readMiss() = readMissW;
        method Bool readRecentLineHit() = readRecentLineHitW;
        method Bool writeHit() = writeHitW;
        method Bool writeMiss() = writeMissW;
        method Bool invalEntry() = invalEntryW;
        method Bool dirtyEntryFlush() = dirtyEntryFlushW;
        method Bool forceInvalLine() = forceInvalLineW;
    endinterface

endmodule



// ===================================================================
//
// BRAM-based local data implementation.
//
// ===================================================================

module mkBRAMCacheLocalData
    // interface:
    (RL_SA_CACHE_LOCAL_DATA#(t_CACHE_ADDR_SZ, t_CACHE_WORD, nWordsPerLine, nSets, nWays))
    provisos (Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Alias#(RL_SA_CACHE_SET_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays), t_SET_METADATA),
              Bits#(t_SET_METADATA, t_SET_METADATA_SZ),
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Alias#(RL_SA_CACHE_WAY_IDX#(nWays), t_CACHE_WAY_IDX),
              Alias#(Tuple2#(t_CACHE_SET_IDX, t_CACHE_WAY_IDX), t_CACHE_DATA_IDX));
    
    // Metadata
    BRAM#(RL_SA_CACHE_SET_IDX#(nSets), t_SET_METADATA) meta <- mkBRAMInitialized(RL_SA_CACHE_SET_METADATA { lru: Vector::genWith(fromInteger),
                                                                                                            ways: Vector::replicate(tagged Invalid) });

    // Values
    Vector#(nWordsPerLine, BRAM_MULTI_READ#(RL_SA_CACHE_DATA_READ_PORTS, t_CACHE_DATA_IDX, t_CACHE_WORD)) data <- replicateM(mkBRAMPseudoMultiRead());

    //
    // getDataIdx --
    //     Convert set and way into a linear address.
    //
    function t_CACHE_DATA_IDX getDataIdx (t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        return tuple2(set, way);
    endfunction


    // ====================================================================
    //
    // Read request FIFOs.  Read requests are buffered through FIFOs in
    // order to break scheduling dependence between reads and writes.
    // They also introduce delay that is needed to meet timing between
    // metadata lookups and data reads.
    //
    // ====================================================================

    FIFO#(Tuple3#(Bit#(TLog#(RL_SA_CACHE_DATA_READ_PORTS)), t_CACHE_SET_IDX, t_CACHE_WAY_IDX)) readDataReqQ <- mkFIFO();

    rule forwardDataReq (True);
        match {.port, .set, .way} = readDataReqQ.first();
        readDataReqQ.deq();

        for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
        begin
            data[b].readPorts[port].readReq(getDataIdx(set, way));
        end
    endrule


    //
    // Metadata access methods
    //
    interface MEMORY_IFC metaData = meta;


    //
    // Data access methods
    //

    // Read all words in a line
    method Action dataReadReq(Integer readPort,
                              RL_SA_CACHE_SET_IDX#(nSets) set,
                              RL_SA_CACHE_WAY_IDX#(nWays) way);
        readDataReqQ.enq(tuple3(fromInteger(readPort), set, way));
    endmethod

    method ActionValue#(Vector#(nWordsPerLine, t_CACHE_WORD)) dataReadRsp(Integer readPort);
        Vector#(nWordsPerLine, t_CACHE_WORD) lineVal;
        for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
        begin
            let v <- data[b].readPorts[readPort].readRsp();
            lineVal[b] = v;
        end

        return lineVal;
    endmethod

    method Bool dataReadNotEmpty(Integer readPort);
        Bool notEmpty = True;
        for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
        begin
            notEmpty = notEmpty && data[b].readPorts[readPort].notEmpty();
        end

        return notEmpty;
    endmethod


    method Action dataWrite(RL_SA_CACHE_SET_IDX#(nSets) set,
                            RL_SA_CACHE_WAY_IDX#(nWays) way,
                            Vector#(nWordsPerLine, Bool) wordMask,
                            Vector#(nWordsPerLine, t_CACHE_WORD) val);
        for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
        begin
            // Only write the word if the mask bit is set
            if (wordMask[b])
            begin
                data[b].write(getDataIdx(set, way), val[b]);
            end
        end
    endmethod

    method Action dataWriteWord(RL_SA_CACHE_SET_IDX#(nSets) set,
                                RL_SA_CACHE_WAY_IDX#(nWays) way,
                                Bit#(TLog#(nWordsPerLine)) wordIdx,
                                t_CACHE_WORD val);
        data[wordIdx].write(getDataIdx(set, way), val);
    endmethod

endmodule

Tuple2#(String, Integer) rl_sa_dbg_scan_desc[16] = {
    tuple2("SA Cache doneQNotEmpty", 1),
    tuple2("SA Cache fillLineQNotEmpty", 1),
    tuple2("SA Cache newReqNotEmpty", 1),
    tuple2("SA Cache fillLineRequestQNotEmpty", 1),

    tuple2("SA Cache evictDirtyForFillQNotEmpty", 1),
    tuple2("SA Cache wordMissQNotEmpty", 1),
    tuple2("SA Cache lineMissQNotEmpty", 1),
    tuple2("SA Cache readHitQNotEmpty", 1),

    tuple2("SA Cache processReqQ1NotEmpty", 1),
    tuple2("SA Cache processReqQ0NotEmpty", 1),
    tuple2("SA Cache writeDataQNotFull", 1),
    tuple2("SA Cache writeDataQNotEmpty", 1),

    tuple2("SA Cache localData_Data2NotEmpty", 1),
    tuple2("SA Cache localData_Data1NotEmpty", 1),
    tuple2("SA Cache localData_Data0NotEmpty", 1),
    tuple2("SA Cache localData_MetaNotEmpty", 1)
};

Vector#(16, Tuple2#(String, Integer)) rlSADebugScanDesc = arrayToVector(rl_sa_dbg_scan_desc);
