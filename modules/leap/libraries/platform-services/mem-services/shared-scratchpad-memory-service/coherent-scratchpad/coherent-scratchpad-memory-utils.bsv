//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/stats_service.bsh"
`include "awb/provides/soft_connections.bsh"


// coherent scratchpad stats constructor

// A function to instantiate a stat tracker. Passed to the multi-cached-memory
// modules below.

typedef function CONNECTED_MODULE#(Empty) f(COH_CACHE_STATS stats) COH_SCRATCH_CACHE_STATS_CONSTRUCTOR;
typedef function CONNECTED_MODULE#(Empty) f(COH_SCRATCH_CONTROLLER_STATS stats) COH_SCRATCH_CONTROLLER_STATS_CONSTRUCTOR;
typedef function CONNECTED_MODULE#(Empty) f(COH_SCRATCH_RING_NODE_STATS stats) COH_SCRATCH_RING_NODE_STATS_CONSTRUCTOR;

//
// mkBasicCoherentScratchpadCacheStats --
//     Shim between an COH_CACHE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicCoherentScratchpadCacheStats#(String tagPrefix,
                                                               String descPrefix,
                                                               COH_CACHE_STATS stats)
    // interface:
    ();

    String tag_prefix = "LEAP_" + tagPrefix;

    STAT_ID statIDs[20] = {
        statName(tag_prefix + "COH_SCRATCH_LOAD_HIT",
                 descPrefix + "Coherent scratchpad load hits"),
        statName(tag_prefix + "COH_SCRATCH_LOAD_MISS",
                 descPrefix + "Coherent scratchpad load misses"),
        statName(tag_prefix + "COH_SCRATCH_LOAD_INVAL_MISS",
                 descPrefix + "Coherent scratchpad load misses due to coherence invalidation"),
        statName(tag_prefix + "COH_SCRATCH_STORE_HIT",
                 descPrefix + "Coherent scratchpad store hits"),
        statName(tag_prefix + "COH_SCRATCH_STORE_CACHELINE_MISS",
                 descPrefix + "Coherent scratchpad store cache-line misses"),
        statName(tag_prefix + "COH_SCRATCH_STORE_PERMISSION_MISS_S",
                 descPrefix + "Coherent scratchpad store permission misses from S state"),
        statName(tag_prefix + "COH_SCRATCH_STORE_PERMISSION_MISS_O",
                 descPrefix + "Coherent scratchpad store permission misses from O state"),
        statName(tag_prefix + "COH_SCRATCH_STORE_INVAL_MISS",
                 descPrefix + "Coherent scratchpad store misses due to coherence invalidation"),
        statName(tag_prefix + "COH_SCRATCH_SELF_INVAL",
                 descPrefix + "Coherent scratchpad self invalidate"),
        statName(tag_prefix + "COH_SCRATCH_SELF_DIRTY_FLUSH",
                 descPrefix + "Coherent scratchpad self dirty flush due to capacity"),
        statName(tag_prefix + "COH_SCRATCH_SELF_CLEAN_FLUSH",
                 descPrefix + "Coherent scratchpad self clean flush due to capacity"),
        statName(tag_prefix + "COH_SCRATCH_COH_INVAL",
                 descPrefix + "Coherent scratchpad invalidate due to coherence"),
        statName(tag_prefix + "COH_SCRATCH_COH_FLUSH",
                 descPrefix + "Coherent scratchpad flush due to coherence"),
        statName(tag_prefix + "COH_SCRATCH_MSHR_RETRY",
                 descPrefix + "Coherent scratchpad cache retry due to unavailable mshr entry"),
        statName(tag_prefix + "COH_SCRATCH_GETX_RETRY",
                 descPrefix + "Coherent scratchpad resend GETX forced by other caches"),
        statName(tag_prefix + "COH_SCRATCH_GETS_UNCACHEABLE",
                 descPrefix + "Coherent scratchpad receive uncacheable response for GETS"),
        statName(tag_prefix + "COH_SCRATCH_IM_UPGRADE",
                 descPrefix + "Coherent scratchpad automatically upgrade from I to M"), 
        statName(tag_prefix + "COH_SCRATCH_IO_UPGRADE",
                 descPrefix + "Coherent scratchpad automatically upgrade from I to O"),
        statName(tag_prefix + "COH_SCRATCH_RESP_FROM_CACHE",
                 descPrefix + "Coherent scratchpad responses sent from caches"),
        statName(tag_prefix + "COH_SCRATCH_RESP_FROM_MEMORY",
                 descPrefix + "Coherent scratchpad responses sent from the memory")
    };
    STAT_VECTOR#(20) sv <- mkStatCounter_Vector(statIDs);
    
    rule readHit (stats.readHit());
        sv.incr(0);
    endrule

    rule readMiss (stats.readMiss());
        sv.incr(1);
    endrule

    rule readInvalMiss (stats.readInvalMiss());
        sv.incr(2);
    endrule

    rule writeHit (stats.writeHit());
        sv.incr(3);
    endrule

    rule writeCacheMiss (stats.writeCacheMiss());
        sv.incr(4);
    endrule

    rule writePermissionMissS (stats.writePermissionMissS());
        sv.incr(5);
    endrule

    rule writePermissionMissO (stats.writePermissionMissO());
        sv.incr(6);
    endrule
    
    rule writeInvalMiss (stats.writeInvalMiss());
        sv.incr(7);
    endrule
    
    rule invalEntry (stats.invalEntry());
        sv.incr(8);
    endrule

    rule dirtyEntryFlush (stats.dirtyEntryFlush());
        sv.incr(9);
    endrule
    
    rule cleanEntryFlush (stats.cleanEntryFlush());
        sv.incr(10);
    endrule

    rule coherenceInval (stats.coherenceInval());
        sv.incr(11);
    endrule

    rule coherenceFlush (stats.coherenceFlush());
        sv.incr(12);
    endrule
    
    rule mshrRetry (stats.mshrRetry());
        sv.incr(13);
    endrule

    rule getxRetry (stats.getxRetry());
        sv.incr(14);
    endrule
    
    rule getsUncacheable (stats.getsUncacheable());
        sv.incr(15);
    endrule

    rule imUpgrade (stats.imUpgrade());
        sv.incr(16);
    endrule

    rule ioUpgrade (stats.ioUpgrade());
        sv.incr(17);
    endrule

    rule respFromCache (stats.respFromCache());
        sv.incr(18);
    endrule

    rule respFromMemory (stats.respFromMemory());
        sv.incr(19);
    endrule

endmodule

module [CONNECTED_MODULE] mkNullCoherentScratchpadCacheStats#(COH_CACHE_STATS stats)
    // interface:
    ();
endmodule

//
// mkBasicCoherentScratchpadControllerStats --
//     Shim between an COH_SCRATCH_CONTROLLER_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicCoherentScratchpadControllerStats#(String tagPrefix,
                                                                    String descPrefix,
                                                                    COH_SCRATCH_CONTROLLER_STATS stats)
    // interface:
    ();

    String tag_prefix = "LEAP_" + tagPrefix;

    STAT_ID statIDs[10] = {
        statName(tag_prefix + "COH_SCRATCH_CTRLR_CLEAN_PUTX",
                 descPrefix + "Coherence controller clean putX received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_DIRTY_PUTX",
                 descPrefix + "Coherence controller dirty putX received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_GETS",
                 descPrefix + "Coherence controller getS received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_GETX",
                 descPrefix + "Coherence controller getX received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_WRITEBACK",
                 descPrefix + "Coherence controller write-back data received"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_OWNERBIT",
                 descPrefix + "Coherence controller ownerbit checkout"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_MEM_DATA",
                 descPrefix + "Coherence controller data received from memory"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_RESP_SENT",
                 descPrefix + "Coherence controller response sent"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_RETRY_PUT",
                 descPrefix + "Coherence controller retry put request"),
        statName(tag_prefix + "COH_SCRATCH_CTRLR_RETRY_GET",
                 descPrefix + "Coherence controller retry get request")
    };
    STAT_VECTOR#(10) sv <- mkStatCounter_Vector(statIDs);
    
    rule cleanPutxReceived (stats.cleanPutxReceived());
        sv.incr(0);
    endrule

    rule dirtyPutxReceived (stats.dirtyPutxReceived());
        sv.incr(1);
    endrule

    rule getsReceived (stats.getsReceived());
        sv.incr(2);
    endrule

    rule getxReceived (stats.getxReceived());
        sv.incr(3);
    endrule

    rule writebackReceived (stats.writebackReceived());
        sv.incr(4);
    endrule

    rule ownerbitCheckout (stats.ownerbitCheckout());
        sv.incr(5);
    endrule

    rule dataReceived (stats.dataReceived());
        sv.incr(6);
    endrule
    
    rule respSent (stats.respSent());
        sv.incr(7);
    endrule

    rule putRetry (stats.putRetry());
        sv.incr(8);
    endrule

    rule getRetry (stats.getRetry());
        sv.incr(9);
    endrule
    
endmodule

module [CONNECTED_MODULE] mkNullCoherentScratchpadControllerStats#(COH_SCRATCH_CONTROLLER_STATS stats)
    // interface:
    ();
endmodule

//
// mkBasicCoherentScratchpadRingNodeStats --
//     Shim between an COH_SCRATCH_RING_NODE_STATS interface and statistics counters.
//     Tag and description prefixes allow the caller to define the prefixes
//     of the statistic.
//
module [CONNECTED_MODULE] mkBasicCoherentScratchpadRingNodeStats#(String tagPrefix,
                                                                  String descPrefix,
                                                                  COH_SCRATCH_RING_NODE_STATS stats)
    // interface:
    ();

    String tag_prefix = "LEAP_" + tagPrefix;

    STAT_ID statIDs[3] = {
        statName(tag_prefix + "COH_SCRATCH_RING_NODE_LOCAL_SENT",
                 descPrefix + "Coherence scratchpad ring node local message sent"),
        statName(tag_prefix + "COH_SCRATCH_RING_NODE_FORWARD",
                 descPrefix + "Coherence scratchpad ring node forward message"),
        statName(tag_prefix + "COH_SCRATCH_RING_NODE_RECEIVED",
                 descPrefix + "Coherence scratchpad ring node message received")
    };
    STAT_VECTOR#(3) sv <- mkStatCounter_Vector(statIDs);
    
    rule localMsgSent (stats.localMsgSent());
        sv.incr(0);
    endrule

    rule fwdMsgSent (stats.fwdMsgSent() != 0);
        sv.incrBy(1, zeroExtend(stats.fwdMsgSent()));
    endrule

    rule msgReceived (stats.msgReceived());
        sv.incr(2);
    endrule
endmodule

module [CONNECTED_MODULE] mkNullCoherentScratchpadRingNodeStats#(COH_SCRATCH_RING_NODE_STATS stats)
    // interface:
    ();
endmodule


// ====================================================================
//
// Coherent scratchpad debug scan node wrappers
//
// ====================================================================

// coherent scratchpad debugScanNode constructor

typedef function CONNECTED_MODULE#(Empty) f(DEBUG_SCAN_FIELD_LIST dlist) COH_SCRATCH_CLIENT_DEBUG_SCAN_NODE_CONSTRUCTOR;

//
// mkCohScratchClientDebugScanNodeFromID --
//     A wrapper that instantiates a debug scan node with a unique client ID and a domain ID
//
module [CONNECTED_MODULE] mkCohScratchClientDebugScanNodeFromID#(Integer domainId,
                                                                 Integer clientId,
                                                                 DEBUG_SCAN_FIELD_LIST dlist)
    // interface:
    ();
    String cohScratchName = "Coherent Scratchpad Client " + integerToString(clientId) + " in Domain " + integerToString(domainId);
    let dbgNode <- mkDebugScanNode(cohScratchName + " (coherent-scratchpad-memory-client.bsv)", dlist);
endmodule

//
// mkCohScratchClientDebugScanNode
//     A wrapper that instantiates a debug scan node for a coherent scratchpad client with a unique string
//
module [CONNECTED_MODULE] mkCohScratchClientDebugScanNode#(String name,
                                                           DEBUG_SCAN_FIELD_LIST dlist)
    // interface:
    ();
    let dbgNode <- mkDebugScanNode(name + " (coherent-scratchpad-memory-client.bsv)", dlist);
endmodule

//
// mkNullCohScratchClientDebugScanNode --
//
module [CONNECTED_MODULE] mkNullCohScratchClientDebugScanNode#(DEBUG_SCAN_FIELD_LIST dlist)
    // interface:
    ();
endmodule


// ====================================================================
//
// Coherent scratchpad controller partition modules
//
// ====================================================================

//
// mkCohScratchControllerAddrPartition --
//
module [CONNECTED_MODULE] mkCohScratchControllerAddrPartition#(SHARED_SCRATCH_MEM_ADDRESS inBaseAddr, 
                                                               SHARED_SCRATCH_MEM_ADDRESS inAddrRange,
                                                               NumTypeParam#(t_IN_DATA_SZ) inDataSz)
    // interface:
    (SHARED_SCRATCH_PARTITION)
    provisos (// Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_IN_DATA_SZ)), t_NATURAL_SZ),
              Bits#(COH_SCRATCH_MEM_VALUE, t_COH_SCRATCH_MEM_VALUE_SZ),
              // Compute the container (scratchpad) index size
              NumAlias#(TLog#(TDiv#(t_COH_SCRATCH_MEM_VALUE_SZ, t_NATURAL_SZ)), t_NATURAL_IDX_SZ));
    
    SHARED_SCRATCH_MEM_ADDRESS baseAddr = inBaseAddr >> fromInteger(valueOf(t_NATURAL_IDX_SZ));
    SHARED_SCRATCH_MEM_ADDRESS addrRange = inAddrRange >> fromInteger(valueOf(t_NATURAL_IDX_SZ));

    method Bool isLocalReq(SHARED_SCRATCH_MEM_ADDRESS addr);
        return ((addr >= baseAddr) && (addr < (baseAddr + addrRange)));
    endmethod

    method SHARED_SCRATCH_MEM_ADDRESS globalToLocalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
        return addr - baseAddr;
    endmethod

    method SHARED_SCRATCH_MEM_ADDRESS localToGlobalAddr(SHARED_SCRATCH_MEM_ADDRESS addr);
        return addr + baseAddr;
    endmethod
        
endmodule

