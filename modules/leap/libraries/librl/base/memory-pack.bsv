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


//
// This package provides a wrapper class that maps underlying indexed storage
// with a fixed word size to a new array of storage with a different word
// size.  Scratchpad memory, that is always presented as a system-wide
// fixed size can thus be marshalled into arbitrary-sized types.
//
// Note:  all type marshalling is in buckets with sizes that are powers of 2.
// While this may waste space it drastically simplifies addressing.
//


import Vector::*;
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;


`include "awb/provides/librl_bsv_base.bsh"

//
// Number of slots in read state buffers.  This value controls the number
// of reads that may be in flight.  It is likely you want this value to be
// equal to (definitely not greater than) the number of scratchpad port ROB
// slots.
//
typedef 32 MEM_PACK_READ_SLOTS;


//
// Number of container read ports needed based on the number of user-visible
// read ports and the packing of objects to containers.  Because all mappings
// flow through mkMemPackMultiRead() below, there must be a single expression
// defining the relationship that works in all cases.
//

// Read port adder for many:1 mapping (0 when mapping is not many:1).
// many:1 mapping requires exactly 1 extra read port.
typedef TMin#(1, MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ))
        MEM_PACK_SMALLER_INTERNAL_READ_PORTS#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

// Read port multiplier for 1:many mapping (1 when mapping is not 1:many)
// 1:many mapping requires this many read ports per user-visible port.
typedef TDiv#(t_DATA_SZ, t_CONTAINER_DATA_SZ)
        MEM_PACK_LARGER_CHUNKS_PER_OBJ#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

// Read ports for all mappings
typedef TMax#(TAdd#(n_READERS, MEM_PACK_SMALLER_INTERNAL_READ_PORTS#(t_DATA_SZ, t_CONTAINER_DATA_SZ)),
              TMul#(n_READERS, MEM_PACK_LARGER_CHUNKS_PER_OBJ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)))
        MEM_PACK_CONTAINER_READ_PORTS#(numeric type n_READERS, numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

//
// Compute the number of objects of desired type that can fit inside a container
// type.  For a given data and container size, one of the two object index sizes
// will always be 0.  This becomes important in MEM_PACK_CONTAINER_ADDR!
//
// For many:1 mapping, the number of objects per container will always
// be a power of 2.  Other values would require a divide.
//
typedef TLog#(TDiv#(t_CONTAINER_DATA_SZ, TExp#(TLog#(t_DATA_SZ))))
        MEM_PACK_SMALLER_OBJ_IDX_SZ#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

typedef TLog#(MEM_PACK_LARGER_CHUNKS_PER_OBJ#(t_DATA_SZ, t_CONTAINER_DATA_SZ))
        MEM_PACK_LARGER_OBJ_IDX_SZ#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);


// ************************************************************************
//
// KEY DATA TYPE:
//
// MEM_PACK_CONTAINER_ADDR is the address type of a container that will
// hold a vector of the desired quantity of the desired data.
//
// The computation works because at least one of MEM_PACK_SMALLER_OBJ_IDX_SZ
// and MEM_PACK_LARGER_OBJ_IDX_SZ must be 0.
//
// ************************************************************************

typedef Bit#(TAdd#(TSub#(t_ADDR_SZ,
                         MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)),
                   MEM_PACK_LARGER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)))
        MEM_PACK_CONTAINER_ADDR#(numeric type t_ADDR_SZ, numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);


// ************************************************************************
//
// Masked Write Version:
// 
// The object index and container address calculation is similar except 
// that for many:1 mapping, the small object is extended to a power of 2 bits
// that is one byte or larger. (This is because we are using byte masks.)
//
// ************************************************************************

// For non many:1 mapping, MEM_PACK_MASKED_WRITE_SMALLER_OBJ_IDX_SZ is always 0
typedef TMul#(TMin#(1, MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)),
        TLog#(TDiv#(t_CONTAINER_DATA_SZ, TMax#(8, TExp#(TLog#(t_DATA_SZ))))))
        MEM_PACK_MASKED_WRITE_SMALLER_OBJ_IDX_SZ#(numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

typedef Bit#(TAdd#(TSub#(t_ADDR_SZ,
                         MEM_PACK_MASKED_WRITE_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)),
                   MEM_PACK_LARGER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)))
        MEM_PACK_MASKED_WRITE_CONTAINER_ADDR#(numeric type t_ADDR_SZ, numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

// Read ports for all mappings
typedef TMax#(n_READERS, TMul#(n_READERS, MEM_PACK_LARGER_CHUNKS_PER_OBJ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)))
        MEM_PACK_MASKED_WRITE_CONTAINER_READ_PORTS#(numeric type n_READERS, numeric type t_DATA_SZ, numeric type t_CONTAINER_DATA_SZ);

//
// mkMemPackMultiRead
//     The general wrapper to use for all allocations.  Map an array indexed
//     by t_ADDR_SZ bits of Bit#(t_DATA_SZ) objects onto backing storage
//     made up of objects of type Bit#(t_CONTAINDER_DATA_SZ).
//
//     This wrapper picks the right implementation module depending on whether
//     there is a 1:1 mapping of objects to containers or a more complicated
//     mapping.
//
module [m] mkMemPackMultiRead#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                               function m#(MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA)) containerMem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (IsModule#(m, a__),
              Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(MEM_PACK_CONTAINER_READ_PORTS#(n_READERS, t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CONTAINER_READERS),
              Alias#(MEM_PACK_CONTAINER_ADDR#(t_ADDR_SZ, t_DATA_SZ, t_CONTAINER_DATA_SZ), t_CONTAINER_ADDR),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA));

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) mem <- containerMem();
    
    //
    // Pick the appropriate packed memory module depending on the relative sizes
    // of the container and the target.
    //
    MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) pack_mem;
    if (valueOf(t_ADDR_SZ) == valueOf(t_CONTAINER_ADDR_SZ))
    begin
        // One object per container
        pack_mem <- mkMemPack1To1(containerDataSz, mem);
    end
    else if (valueOf(t_ADDR_SZ) > valueOf(t_CONTAINER_ADDR_SZ))
    begin
        // Multiple objects per container
        pack_mem <- mkMemPackManyTo1(containerDataSz, mem);
    end
    else
    begin
        // Object bigger than one container.  Use multiple containers for
        // each object.
        pack_mem <- mkMemPack1ToMany(containerDataSz, mem);
    end

    return pack_mem;
endmodule


//
// mkMemPackMultiReadMaskWrite --
//     This is similar to mkMemPackMultiRead but it uses masked writes for the case
// where multiple objects share a container.  
//
module [m] mkMemPackMultiReadMaskWrite#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                                        function m#(MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA, t_CONTAINER_MASK)) containerMem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (IsModule#(m, a__),
              Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              NumAlias#(MEM_PACK_MASKED_WRITE_CONTAINER_READ_PORTS#(n_READERS, t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CONTAINER_READERS),
              Alias#(MEM_PACK_MASKED_WRITE_CONTAINER_ADDR#(t_ADDR_SZ, t_DATA_SZ, t_CONTAINER_DATA_SZ), t_CONTAINER_ADDR),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              NumAlias#(TDiv#(t_CONTAINER_DATA_SZ, 8), t_CONTAINER_DATA_BYTES_PER_WORD),
              Alias#(Vector#(t_CONTAINER_DATA_BYTES_PER_WORD, Bool), t_CONTAINER_MASK),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA));

    // Instantiate the underlying memory.
    MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA, t_CONTAINER_MASK) mem <- containerMem();
    
    //
    // Pick the appropriate packed memory module depending on the relative sizes
    // of the container and the target.
    //
    MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA) pack_mem;
    if (valueOf(t_ADDR_SZ) == valueOf(t_CONTAINER_ADDR_SZ))
    begin
        // One object per container
        MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) m1 <- mkMultiReadMaskedWriteIfcToMultiReadMemIfc(mem);
        pack_mem <- mkMemPack1To1(containerDataSz, m1);
    end
    else if (valueOf(t_ADDR_SZ) > valueOf(t_CONTAINER_ADDR_SZ))
    begin
        // Multiple objects per container
        pack_mem <- mkMemPackManyTo1WithMaskedWrite(containerDataSz, mem);
    end
    else
    begin
        // Object bigger than one container.  Use multiple containers for each object.
        MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) m2 <- mkMultiReadMaskedWriteIfcToMultiReadMemIfc(mem);
        pack_mem <- mkMemPack1ToMany(containerDataSz, m2);
    end

    return pack_mem;
endmodule


// ========================================================================
//
// Internal modules.
//
// ========================================================================

//
// mkMemPack1To1 --
//     Map desired storage to a container for the case where one object
//     is stored per container.  The address spaces of the container and
//     and desired data are thus identical and the mapping is trivial.
//
module mkMemPack1To1#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                      MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) mem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA));

    //
    // Read ports
    //
    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for(Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr) = mem.readPorts[p].readReq(unpack(zeroExtendNP(pack(addr))));

                method ActionValue#(t_DATA) readRsp();
                    let v <- mem.readPorts[p].readRsp();
                    return unpack(truncateNP(pack(v)));
                endmethod

                method t_DATA peek() = unpack(truncateNP(pack(mem.readPorts[p].peek())));
                method Bool notEmpty() = mem.readPorts[p].notEmpty();
                method Bool notFull() = mem.readPorts[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    //
    // Write
    //
    method Action write(t_ADDR addr, t_DATA val);
        mem.write(unpack(zeroExtendNP(pack(addr))), unpack(zeroExtendNP(pack(val))));
    endmethod

    method Bool writeNotFull() = mem.writeNotFull();
endmodule

//
// mkMemPackManyTo1 --
//     Pack multiple objects into a single container object.
//
module mkMemPackManyTo1#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                         MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) mem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA),
              Alias#(Bit#(MEM_PACK_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)), t_OBJ_IDX),
              Bits#(t_OBJ_IDX, t_OBJ_IDX_SZ),

              // Arrangement of objects packed in a container.  Objects are evenly
              // spaced to make packed values easier to read while debugging.
              Alias#(Vector#(TExp#(t_OBJ_IDX_SZ), Bit#(TDiv#(t_CONTAINER_DATA_SZ, TExp#(t_OBJ_IDX_SZ)))), t_PACKED_CONTAINER));

    // Write state
    FIFOF#(t_ADDR) writeAddrQ <- mkFIFOF();
    FIFOF#(t_DATA) writeDataQ <- mkFIFOF();
    Reg#(Bool) writeActive <- mkReg(False);

    // Read request info holds the address of the requested data within the
    // container.
    Vector#(n_READERS, FIFO#(t_OBJ_IDX)) readReqInfoQ <- replicateM(mkSizedFIFO(valueOf(MEM_PACK_READ_SLOTS)));

    //
    // addrSplit --
    //     Split an incoming address into two components:  the container address
    //     and the index of the requested object within the container.
    //
    function Tuple2#(t_CONTAINER_ADDR, t_OBJ_IDX) addrSplit(t_ADDR addr);
        Bit#(t_ADDR_SZ) p_addr = pack(addr);
        return tuple2(unpack(p_addr[valueOf(t_ADDR_SZ)-1 : valueOf(t_OBJ_IDX_SZ)]), p_addr[valueOf(t_OBJ_IDX_SZ)-1 : 0]);
    endfunction


    //
    // startRMW --
    //     The beginning of a read-modify-write.
    //
    rule startRMW (! writeActive);
        let addr = writeAddrQ.first();
        match {.c_addr, .o_idx} = addrSplit(addr);

        // Read port 0 is reserved for RMW
        mem.readPorts[0].readReq(c_addr);
    
        writeActive <= True;
    endrule

    //
    // finishRMW --
    //     Process read response for a write.  Update the object within the
    //     container and write it back.
    //
    rule finishRMW (writeActive);
        let addr = writeAddrQ.first();
        writeAddrQ.deq();
        
        let val = writeDataQ.first();
        writeDataQ.deq();

        // Pack the current data into a vector of the number of objects
        // per container.
        let d <- mem.readPorts[0].readRsp();
        t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
        
        // Update the object in the container and write it back.
        match {.c_addr, .o_idx} = addrSplit(addr);
        pack_data[o_idx] = zeroExtendNP(pack(val));
        mem.write(c_addr, unpack(zeroExtendNP(pack(pack_data))));
        
        writeActive <= False;
    endrule


    //
    // Methods
    //
    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr) if (! writeAddrQ.notEmpty());
                    match {.c_addr, .o_idx} = addrSplit(addr);
                    // Port 0 is reserved for reads to service read-modify-write.
                    // The container memory has an extra read port, so shift
                    // all requests up 1.
                    mem.readPorts[p + 1].readReq(c_addr);

                    readReqInfoQ[p].enq(o_idx);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let o_idx = readReqInfoQ[p].first();
                    readReqInfoQ[p].deq();

                    // Receive the data and return the desired object from the container.
                    let d <- mem.readPorts[p + 1].readRsp();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method t_DATA peek();
                    let o_idx = readReqInfoQ[p].first();
    
                    // Receive the data and return the desired object from the container.
                    let d = mem.readPorts[p + 1].peek();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method Bool notEmpty() = mem.readPorts[p + 1].notEmpty();
                method Bool notFull() = mem.readPorts[p + 1].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        writeAddrQ.enq(addr);
        writeDataQ.enq(val);
    endmethod

    method Bool writeNotFull() = writeAddrQ.notFull();
endmodule

//
// mkMemPackManyTo1WithMaskedWrite --
//     Pack multiple objects into a single container object using masked writes.
//
module mkMemPackManyTo1WithMaskedWrite#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                                        MEMORY_MULTI_READ_MASKED_WRITE_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA, t_CONTAINER_MASK) mem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA),
              // Compute the natural size in bits.  The natural size is rounded up to
              // a power of 2 bits that is one byte or larger.
              Max#(8, TExp#(TLog#(t_DATA_SZ)), t_NATURAL_SZ),
              // Compute the object index within a container 
              Alias#(Bit#(MEM_PACK_MASKED_WRITE_SMALLER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)), t_OBJ_IDX),
              Bits#(t_OBJ_IDX, t_OBJ_IDX_SZ),
              // Arrangement of objects packed in a container.  Objects are evenly
              // spaced to make packed values easier to read while debugging.
              Alias#(Vector#(TExp#(t_OBJ_IDX_SZ), Bit#(TDiv#(t_CONTAINER_DATA_SZ, TExp#(t_OBJ_IDX_SZ)))), t_PACKED_CONTAINER),
              // Container byte mask
              NumAlias#(TDiv#(t_CONTAINER_DATA_SZ, 8), t_CONTAINER_DATA_BYTES_PER_WORD),
              Alias#(Vector#(t_CONTAINER_DATA_BYTES_PER_WORD, Bool), t_CONTAINER_MASK));

    // Read request info holds the address of the requested data within the container.
    Vector#(n_READERS, FIFO#(t_OBJ_IDX)) readReqInfoQ <- replicateM(mkSizedFIFO(valueOf(MEM_PACK_READ_SLOTS)));

    //
    // addrSplit --
    //     Split an incoming address into two components:  the container address
    //     and the index of the requested object within the container.
    //
    function Tuple2#(t_CONTAINER_ADDR, t_OBJ_IDX) addrSplit(t_ADDR addr);
        Bit#(t_ADDR_SZ) p_addr = pack(addr);
        return tuple2(unpack(p_addr[valueOf(t_ADDR_SZ)-1 : valueOf(t_OBJ_IDX_SZ)]), p_addr[valueOf(t_OBJ_IDX_SZ)-1 : 0]);
    endfunction
    
    //
    // computeByteMask --
    //     Compute the byte mask of an object within a container given the object index.
    //
    function t_CONTAINER_MASK computeByteMask(t_OBJ_IDX idx);
        // Build a mask of valid bytes
        Vector#(TExp#(t_OBJ_IDX_SZ), Bit#(TDiv#(t_NATURAL_SZ, 8))) b_mask = replicate(0);
        b_mask[idx] = -1;
        // Size should match.  Resize avoids a proviso.
        return unpack(resize(pack(b_mask)));
    endfunction

    //
    // Methods
    //
    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                method Action readReq(t_ADDR addr);
                    match {.c_addr, .o_idx} = addrSplit(addr);
                    mem.readPorts[p].readReq(c_addr);
                    readReqInfoQ[p].enq(o_idx);
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    let o_idx = readReqInfoQ[p].first();
                    readReqInfoQ[p].deq();
                    // Receive the data and return the desired object from the container.
                    let d <- mem.readPorts[p].readRsp();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method t_DATA peek();
                    let o_idx = readReqInfoQ[p].first();
                    // Receive the data and return the desired object from the container.
                    let d = mem.readPorts[p].peek();
                    t_PACKED_CONTAINER pack_data = unpack(truncateNP(pack(d)));
                    return unpack(truncateNP(pack_data[o_idx]));
                endmethod

                method Bool notEmpty() = mem.readPorts[p].notEmpty();
                method Bool notFull() = mem.readPorts[p].notFull();
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        match {.c_addr, .o_idx} = addrSplit(addr);
        // Put the data at the right place in the container
        t_PACKED_CONTAINER pack_data = unpack(0);
        pack_data[o_idx] = zeroExtendNP(pack(val));
        mem.write(c_addr, unpack(zeroExtendNP(pack(pack_data))), computeByteMask(o_idx));
    endmethod

    method Bool writeNotFull() = mem.writeNotFull();
endmodule

//
// mkMemPack1ToMany --
//     Spread one object across multiple container objects.
//
module mkMemPack1ToMany#(NumTypeParam#(t_CONTAINER_DATA_SZ) containerDataSz,
                         MEMORY_MULTI_READ_IFC#(n_CONTAINER_READERS, t_CONTAINER_ADDR, t_CONTAINER_DATA) mem)
    // interface:
    (MEMORY_MULTI_READ_IFC#(n_READERS, t_ADDR, t_DATA))
    provisos (Bits#(t_ADDR, t_ADDR_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(t_CONTAINER_ADDR, t_CONTAINER_ADDR_SZ),
              Alias#(Bit#(t_CONTAINER_DATA_SZ), t_CONTAINER_DATA),
              Alias#(Bit#(MEM_PACK_LARGER_OBJ_IDX_SZ#(t_DATA_SZ, t_CONTAINER_DATA_SZ)), t_OBJ_IDX),
              // Vector of multiple containers holding one object
              NumAlias#(MEM_PACK_LARGER_CHUNKS_PER_OBJ#(t_DATA_SZ, t_CONTAINER_DATA_SZ), n_CHUNKS_PER_OBJ),
              Alias#(Vector#(n_CHUNKS_PER_OBJ, t_CONTAINER_DATA), t_PACKED_CONTAINER));

    // Write state
    FIFOF#(Tuple2#(t_ADDR, t_PACKED_CONTAINER)) writeQ <- mkBypassFIFOF();
    Reg#(t_OBJ_IDX) reqIdx <- mkReg(0);

    let chunks_per_obj = valueOf(n_CHUNKS_PER_OBJ);

    //
    // Need multiple containers for a single object, so the container
    // address is a function of the incoming address and the number of
    // container objects per base object.
    //
    function t_CONTAINER_ADDR addrContainer(t_ADDR addr, t_OBJ_IDX objIdx);
        t_CONTAINER_ADDR ext_addr = unpack(zeroExtendNP(pack(addr)));
        return unpack(pack(ext_addr) * fromInteger(chunks_per_obj) + zeroExtendNP(objIdx));
    endfunction


    //
    // writeData --
    //     Break down an incoming write request into multiple writes to containers.
    //
    rule writeData (True);
        match {.addr, .data} = writeQ.first();

        let c_addr = addrContainer(addr, reqIdx);
        mem.write(c_addr, data[reqIdx]);

        if (reqIdx == fromInteger(valueOf(TSub#(n_CHUNKS_PER_OBJ, 1))))
        begin
            writeQ.deq();
            reqIdx <= 0;
        end
        else
        begin
            reqIdx <= reqIdx + 1;
        end
    endrule


    Vector#(n_READERS, MEMORY_READER_IFC#(t_ADDR, t_DATA)) portsLocal = newVector();

    for (Integer p = 0; p < valueOf(n_READERS); p = p + 1)
    begin
        // Starting port in underlying memory.
        Integer p_base = p * chunks_per_obj;

        portsLocal[p] =
            interface MEMORY_READER_IFC#(t_ADDR, t_DATA);
                //
                // Only allowed to start a read if a write is not in progress.
                // This preserves read/write order.
                //
                method Action readReq(t_ADDR addr) if (! writeQ.notEmpty());
                    // Separate ports are allocated for each chunk associated with
                    // a read request.  Start all reads together.
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        mem.readPorts[p_base + cp].readReq(addrContainer(addr, fromInteger(cp)));
                    end
                endmethod

                method ActionValue#(t_DATA) readRsp();
                    t_PACKED_CONTAINER v = newVector();
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        v[cp] <- mem.readPorts[p_base + cp].readRsp();
                    end

                    return unpack(truncateNP(pack(v)));
                endmethod

                method t_DATA peek();
                    t_PACKED_CONTAINER v = newVector();
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        v[cp] = mem.readPorts[p_base + cp].peek();
                    end

                    return unpack(truncateNP(pack(v)));
                endmethod

                method Bool notEmpty();
                    Bool not_empty = True;
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        not_empty = not_empty && mem.readPorts[p_base + cp].notEmpty();
                    end

                    return not_empty;
                endmethod

                method Bool notFull();
                    Bool not_full = ! writeQ.notEmpty();
                    for (Integer cp = 0; cp < chunks_per_obj; cp = cp + 1)
                    begin
                        not_full = not_full && mem.readPorts[p_base + cp].notFull();
                    end

                    return not_full;
                endmethod
            endinterface;
    end

    interface readPorts = portsLocal;

    method Action write(t_ADDR addr, t_DATA val);
        t_PACKED_CONTAINER write_data = unpack(zeroExtendNP(pack(val)));
        writeQ.enq(tuple2(addr, write_data));
    endmethod

    method Bool writeNotFull() = writeQ.notFull();
endmodule

