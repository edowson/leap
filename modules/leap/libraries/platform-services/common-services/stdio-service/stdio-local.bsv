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

import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import List::*;
import ConfigReg::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv.bsh"
`include "awb/provides/common_services.bsh"

// FILE handle
typedef Bit#(8) STDIO_FILE;

typedef enum {
   STDIO_STDOUT = 0,
   STDIO_STDIN = 1,
   STDIO_STDERR = 2
}
STDIO_STD_FILES
    deriving (Eq, Bits);


// Maximum number of read requests in flight
typedef 4 STDIO_MAX_READS_IN_FLIGHT;
// Maximum elements per read request.  Varies with element size due to
// buffering requirements.
typedef TDiv#(TDiv#(32768, STDIO_MAX_READS_IN_FLIGHT), SizeOf#(t_DATA))
    STDIO_MAX_ELEM_PER_READ#(type t_DATA);
typedef Bit#(TLog#(STDIO_MAX_ELEM_PER_READ#(t_DATA))) STDIO_NUM_READ_ELEMS#(type t_DATA);

// Pick a power of 2!
typedef Bit#(32) STDIO_REQ_RING_CHUNK;
typedef Bit#(32) STDIO_RSP_RING_CHUNK;

//
// For now, RRR does not provide virtual channels for each service.  As
// a result, it is possible to deadlock the shared RRR I/O channel if
// responses to read requests back up.  Instead of forcing each STDIO
// client to manage buffers, the implementation here guarantees to provide
// buffering for all outstanding read requests.  (This would also let us
// replace RRR with virtual channels and change only the code here to
// eliminate the buffering.
//
interface STDIO#(type t_DATA);
    // fopen is a request/response interface, returning the file handle
    method Action fopen_req(GLOBAL_STRING_UID nameID, GLOBAL_STRING_UID modeID);
    method ActionValue#(STDIO_FILE) fopen_rsp();
    method Action fclose(STDIO_FILE file);

    method Action popen_req(GLOBAL_STRING_UID nameID, Bool forRead);
    method ActionValue#(STDIO_FILE) popen_rsp();
    method Action pclose(STDIO_FILE file);


    // Start a read that will stream back nmemb elements serially.  The
    // implementation guarantees to provide local buffering sufficient to
    // hold the full response, avoiding the need for client buffer management.
    method Action fread_req(STDIO_FILE file,
                            STDIO_NUM_READ_ELEMS#(t_DATA) nmemb) provisos(Bits#(t_DATA, t_DATA_SZ));

    // Convenience method for making the largest request possible
    method Action freadMax_req(STDIO_FILE file);

    // Return either one element from a read or Invalid for EOF.  Responses
    // from a single read request terminate on EOF even if fewer responses are
    // returned than originally requested.
    method ActionValue#(Maybe#(t_DATA)) fread_rsp();

    // Number of reads currently in flight.  This method enables clients
    // to track and consume results of all read requests, especially when
    // some read returns EOF.  Following EOF, the client must continue to
    // sink read responses (which will all return EOF) until no reads are
    // in flight.
    method Bit#(TLog#(TAdd#(1, STDIO_MAX_READS_IN_FLIGHT))) fread_numInFlight();


    // The list of arguments to fwrite may be up to STDIO_WRITE_MAX elements
    method Action fwrite(STDIO_FILE file, List#(t_DATA) args);

    // The list of arguments to printf may be up to STDIO_WRITE_MAX elements
    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    method Action fprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID, List#(t_DATA) args);

    // Similar to fprintf, but takes a vector instead of a list.  User
    // code is unlikely to need this.  It is used internally here.
    method Action vfprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID,
                           Vector#(STDIO_WRITE_MAX, t_DATA) data,
                           STDIO_NUM_DATA numData);

    // sprintf is a request/response interface, allocating a GLOBAL_STRING_UID
    // on the host to hold the new string.  The new string remains allocated
    // until released by a sprintf_delete call.
    method Action sprintf_req(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    method ActionValue#(GLOBAL_STRING_UID) sprintf_rsp();

    // Delete a dynamically allocated global string (e.g. one created by
    // sprintf_req).
    method Action string_delete(GLOBAL_STRING_UID strID);

    method Action fflush(STDIO_FILE file);
    method Action rewind(STDIO_FILE file);

    // sync request/response guarantees that all previous commands have been
    // received by the host.  The LEAP run-time system automatically
    // synchronizes state at the end of run, so use of these methods is
    // optional.  When hostSync is True, the host also invokes the libC
    // sync() system call.
    method Action sync_req(Bool hostSync);
    method Action sync_rsp();

    // Internal method used by mkStdio_CondPrintf
    method STDIO_REQ_RING_CHUNK cond_mask_update();
endinterface

//
// Payload on request chain
//
typedef struct
{
    STDIO_REQ_RING_CHUNK chunk;
    Bool eom;

    // Set on special messages requesting that each ring stop flush all
    // pending requests.
    Bool sync;

    // Set on special messages to initialize conditional mask for
    // mkStdio_CondPrintf.
    Bool condMask;
}
STDIO_REQ_RING_MSG
    deriving (Eq, Bits);


// Maximum number of data arguments for writes
typedef 8 STDIO_WRITE_MAX;

typedef enum
{
    STDIO_REQ_FCLOSE,
    STDIO_REQ_FFLUSH,
    STDIO_REQ_FOPEN,
    STDIO_REQ_FPRINTF,
    STDIO_REQ_FREAD,
    STDIO_REQ_FWRITE,
    STDIO_REQ_PCLOSE,
    STDIO_REQ_POPEN,
    STDIO_REQ_REWIND,
    STDIO_REQ_SPRINTF,
    STDIO_REQ_STRING_DELETE,
    STDIO_REQ_SYNC,
    STDIO_REQ_SYNC_SYSTEM
}
STDIO_REQ_COMMAND
    deriving (Eq, Bits);

//
// STDIO_CLIENT_ID is used to identify a particular standard I/O instance on
// the response ring.
//
typedef Bit#(8) STDIO_CLIENT_ID;

typedef enum
{
    STDIO_RSP_FOPEN,
    STDIO_RSP_FREAD,
    STDIO_RSP_FREAD_EOF,            // End of file (no payload in packet)
    STDIO_RSP_POPEN,
    STDIO_RSP_SYNC,
    STDIO_RSP_SYNC_SYSTEM,
    STDIO_RSP_SPRINTF
}
STDIO_RSP_OP
    deriving (Eq, Bits);

typedef Bit#(4) STDIO_NUM_DATA;

//
// STDIO_REQ_HEADER is sent at the beginning of all requests sent to software.
//
typedef struct
{
    GLOBAL_STRING_UID text;
    Bit#(2) unused;
    STDIO_NUM_DATA numData;         // Number of elements in data vector
    Bit#(2) dataSize;               // Size of data elements (1, 2, 4 or 8 bytes)
    STDIO_CLIENT_ID clientID;       // This nodes response ring ID
    STDIO_FILE fileHandle;          // Used only for commands refering to a file
    Bit#(8) command;                // STDIO_REQ_COMMAND
}
STDIO_REQ_HEADER
    deriving (Eq, Bits);

//
// STDIO_REQ is marshalled over the request ring and sent to software.
//
typedef struct
{
    // Number of elements actually transmitted varies, depending
    // on the value of numData.
    Vector#(STDIO_WRITE_MAX, t_DATA) data;

    STDIO_REQ_HEADER header;
}
STDIO_REQ#(type t_DATA)
    deriving (Eq, Bits);

typedef struct
{
    Bool eom;                       // End of marshalled stream
    Bit#(2) nValid;                 // Number of valid demarshalled values in
                                    // the packet (meaningful only for 8 and
                                    // 16 bit data).
    STDIO_RSP_RING_CHUNK data;
    STDIO_RSP_OP operation;
}
STDIO_RSP
    deriving (Eq, Bits);

typedef enum
{
    STDIO_REQ_IDLE,
    STDIO_REQ_SEND_REQ
}
STDIO_REQ_STATE
    deriving (Eq, Bits);


module [CONNECTED_MODULE] mkStdIO
    // interface:
    (STDIO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Add#(a__, 32, TMul#(STDIO_WRITE_MAX, t_DATA_SZ)));
    
    if ((valueOf(t_DATA_SZ) != 8) &&
        (valueOf(t_DATA_SZ) != 16) &&
        (valueOf(t_DATA_SZ) != 32) &&
        (valueOf(t_DATA_SZ) != 64))
    begin
        error("Unsupported mkStdIO data size (" + integerToString(valueOf(t_DATA_SZ)) + ")");
    end


    // ====================================================================
    //
    //   Response ring -- host to FPGA.
    //
    // ====================================================================

    // Response ring is addressable, since responses are to specific clients.
    CONNECTION_ADDR_RING#(STDIO_CLIENT_ID, STDIO_RSP) rspChain <-
        mkConnectionAddrRingDynNode("stdio_rsp_ring");

    STDIO_DEMARSHALLER#(STDIO_REQ_RING_CHUNK, t_DATA) dem <- mkStdIORspDemarshaller();

    // Track number of fread requests in flight
    COUNTER#(TLog#(TAdd#(1, STDIO_MAX_READS_IN_FLIGHT))) freadsInFlight <- mkLCounter(0);
    // Buffer for end of marshalled message stream marker, used for tracking
    // reads in flight.
    FIFO#(Bool) freadEOM <- mkFIFO();

    // Buffer for read responses
    FIFOF#(Tuple3#(t_DATA, Bool, Bool)) freadRspBuf <-
        mkSizedBRAMFIFOF(valueOf(TMul#(STDIO_MAX_READS_IN_FLIGHT,
                                       STDIO_MAX_ELEM_PER_READ#(t_DATA))));

    //
    // Forward fread responses to the demarshaller.
    //
    Reg#(Bit#(1)) alternate <- mkReg(0);
    rule freadDemEnq (rspChain.first().operation == STDIO_RSP_FREAD);
        let rsp = rspChain.first();
        rspChain.deq();

        dem.enq(rsp.data, resize(rsp.nValid) + 1);

        if (valueOf(t_DATA_SZ) <= 32)
        begin
            // Data fits in a single flit
            freadEOM.enq(rsp.eom);
        end
        else
        begin
            // 64 bit data doesn't fit in a single flit.  Only every other
            // flit has meaningful metadata.
            if (alternate == 1) freadEOM.enq(rsp.eom);
            alternate <= alternate ^ 1;
        end
    endrule

    //
    // Buffer the output of the demarshaller.  This guarantees sufficient
    // space to store all possible outstanding read requests and avoids
    // deadlock of the RRR channel.
    //
    rule freadRspBuffer (True);
        let r = dem.first();
        dem.deq();
        
        // Associate the end of message flag with a value coming from the
        // demarshaller.
        Bool is_eom = False;
        if (dem.isLast)
        begin
            is_eom = freadEOM.first();
            freadEOM.deq();
        end

        freadRspBuf.enq(tuple3(r, is_eom, False));
    endrule

    //
    // End of file files through the freadRspBuf too in order to stay
    // synchronized with read responses.
    //
    rule eof ((rspChain.first().operation == STDIO_RSP_FREAD_EOF) &&
              ! dem.notEmpty);
        rspChain.deq();
        freadRspBuf.enq(tuple3(?, True, True));
    endrule


    // ====================================================================
    //
    //   Request ring -- FPGA to host.
    //
    // ====================================================================

    function STDIO_REQ_HEADER genHeader(STDIO_REQ_COMMAND command);
        STDIO_REQ_HEADER header = ?;
        header.command = zeroExtend(pack(command));
        header.clientID = rspChain.nodeID;
        header.dataSize = fromInteger(valueOf(TSub#(TLog#(t_DATA_SZ), 3)));
        header.numData = 0;

        return header;
    endfunction

    // Request ring.  All requests are handled by the service.
    CONNECTION_CHAIN#(STDIO_REQ_RING_MSG) reqChain <-
        mkConnectionChain("stdio_req_ring");

    STDIO_MARSHALLER#(STDIO_REQ_RING_CHUNK, t_DATA) mar <- mkStdIOReqMarshaller();
    FIFOF#(STDIO_REQ#(t_DATA)) newReqQ <- mkBypassFIFOF();

    Reg#(STDIO_REQ_STATE) reqState <- mkReg(STDIO_REQ_IDLE);
    Reg#(Bool) reqNotBusy <- mkReg(True);
    FIFOF#(Bool) doSyncReqQ <- mkFIFOF();
    FIFO#(Bool) doSyncRspQ <- mkFIFO();

    Wire#(STDIO_REQ_RING_CHUNK) condMask <- mkWire();


    //
    // marshallReq --
    //     Marshall this node's requests in a narrower channel.
    //
    rule marshallReq (True);
        if (newReqQ.notEmpty)
        begin
            // Forward normal request
            mar.enq(newReqQ.first);
            newReqQ.deq();
        end
        else if (doSyncReqQ.notEmpty)
        begin
            doSyncReqQ.deq();

            if (rspChain.nodeID == rspChain.maxID)
            begin
                // This is the last node in the chain.  Force a round-trip
                // message to the host and then declare all STDIO in sync.
                let header = genHeader(STDIO_REQ_SYNC_SYSTEM);
                mar.enq(STDIO_REQ { data: ?, header: header });
            end
            else
            begin
                // Not the last node in the ring.  Prepare to forward
                // the sync token to the next node.
                doSyncRspQ.enq(?);
            end
        end
    endrule


    //
    // sendLocalReq --
    //     Send local request.
    //
    rule sendLocalReq (reqState == STDIO_REQ_SEND_REQ);
        let msg = STDIO_REQ_RING_MSG { chunk: mar.first,
                                       eom: mar.isLast,
                                       sync: False,
                                       condMask: False };
        reqChain.sendToNext(msg);

        if (mar.isLast())
        begin
            reqState <= STDIO_REQ_IDLE;
        end

        mar.deq();
    endrule

    //
    // manageReq --
    //     Forward requests from others and switch to local sending when
    //     appropriate.  Local requests have priority.
    //
    rule forwardReq (reqState == STDIO_REQ_IDLE);
        if (mar.notEmpty && reqNotBusy)
        begin
            reqState <= STDIO_REQ_SEND_REQ;
        end
        else
        begin
            let msg <- reqChain.recvFromPrev();
            reqNotBusy <= msg.eom;

            if (msg.condMask)
            begin
                // Update of conditional mask for mkStdio_CondPrintf.  The
                // conditional mask is the size of one chunk.
                condMask <= msg.chunk;
                reqChain.sendToNext(msg);
            end
            else if (! msg.sync)
            begin
                // Normal message.  Forward it.
                reqChain.sendToNext(msg);
            end
            else
            begin
                // Host asking for synchronization
                doSyncReqQ.enq(?);
            end
        end
    endrule

    //
    // fwdSyncReq --
    //     Each STDIO node holds the host's request to sync state until the
    //     handshaking is complete.  Once the node's sync is complete, the
    //     sync request is sent along the request ring to the next node.
    //
    (* descending_urgency = "forwardReq, fwdSyncReq" *)
    rule fwdSyncReq (reqState == STDIO_REQ_IDLE);
        doSyncRspQ.deq();

        let msg = STDIO_REQ_RING_MSG { chunk: ?,
                                       eom: True,
                                       sync: True,
                                       condMask: False };
        reqChain.sendToNext(msg);
    endrule

    //
    // getSyncRsp --
    //     Host has received sync.  Now ready to forward to the next node.
    //
    (* descending_urgency = "getSyncRsp, marshallReq" *)
    rule getSyncRsp (rspChain.first().operation == STDIO_RSP_SYNC_SYSTEM);
        rspChain.deq();
        doSyncRspQ.enq(?);
    endrule


    // ====================================================================
    //
    //   Methods & functions to implement them
    //
    // ====================================================================

    function Action do_write(STDIO_REQ_COMMAND command,
                             STDIO_FILE file,
                             GLOBAL_STRING_UID msgID,
                             List#(t_DATA) args);
    action
        let header = genHeader(command);
        header.fileHandle = file;
        header.text = msgID;
        header.numData = fromInteger(List::length(args));

        let data = stdioListToVec(args);

        newReqQ.enq(STDIO_REQ { data: data, header: header });
    endaction
    endfunction


    method Action fopen_req(GLOBAL_STRING_UID nameID, GLOBAL_STRING_UID modeID);
        let header = genHeader(STDIO_REQ_FOPEN);
        header.text = nameID;

        // Jam the extra 32-bit modeID argument in the data vector
        Vector#(STDIO_WRITE_MAX, t_DATA) data = unpack({ ?, modeID });
        header.numData = fromInteger(valueOf(TDiv#(SizeOf#(GLOBAL_STRING_UID),
                                                   t_DATA_SZ)));

        newReqQ.enq(STDIO_REQ { data: data, header: header });
    endmethod

    method ActionValue#(STDIO_FILE) fopen_rsp() if (rspChain.first().operation == STDIO_RSP_FOPEN);
        let file = truncate(rspChain.first().data);
        rspChain.deq();
        return file;
    endmethod

    method Action fclose(STDIO_FILE file);
        let header = genHeader(STDIO_REQ_FCLOSE);
        header.fileHandle = file;

        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod


    method Action popen_req(GLOBAL_STRING_UID nameID, Bool forRead);
        let header = genHeader(STDIO_REQ_POPEN);
        header.text = nameID;
        // Store read vs. write request in fileHandle
        header.fileHandle = zeroExtend(pack(forRead));

        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod

    method ActionValue#(STDIO_FILE) popen_rsp() if (rspChain.first().operation == STDIO_RSP_POPEN);
        let file = truncate(rspChain.first().data);
        rspChain.deq();
        return file;
    endmethod

    method Action pclose(STDIO_FILE file);
        let header = genHeader(STDIO_REQ_PCLOSE);
        header.fileHandle = file;

        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod


    method Action fread_req(STDIO_FILE file,
                            STDIO_NUM_READ_ELEMS#(t_DATA) nmemb) if (freadsInFlight.value != fromInteger(valueOf(STDIO_MAX_READS_IN_FLIGHT)));
        let header = genHeader(STDIO_REQ_FREAD);
        header.fileHandle = file;
        // Jam the number of elements requested in the text field
        header.text = zeroExtendNP(nmemb);

        freadsInFlight.up();
        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod

    method Action freadMax_req(STDIO_FILE file) if (freadsInFlight.value != fromInteger(valueOf(STDIO_MAX_READS_IN_FLIGHT)));
        let header = genHeader(STDIO_REQ_FREAD);
        header.fileHandle = file;
        // Jam the number of elements requested in the text field
        header.text = fromInteger(valueOf(TSub#(STDIO_MAX_ELEM_PER_READ#(t_DATA), 1)));

        freadsInFlight.up();
        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod

    //
    // Firing rules for fread_rsp are a bit complicated:
    //   The rule may fire either if a read response is available or EOF has
    //   been signalled.  The rule must avoid firing if EOF is being signalled
    //   but a read response is still being processed in the demarshaller
    //   and hasn't yet flowed to the freadRspBuf.
    //
    method ActionValue#(Maybe#(t_DATA)) fread_rsp();
        match {.d, .eom, .eof} = freadRspBuf.first();
        freadRspBuf.deq();

        // Last flit for this read request?
        if (eom)
        begin
            // Read is done
            freadsInFlight.down();
        end

        return (! eof ? tagged Valid d : tagged Invalid);
    endmethod

    method Bit#(TLog#(TAdd#(1, STDIO_MAX_READS_IN_FLIGHT))) fread_numInFlight();
        return freadsInFlight.value();
    endmethod


    method Action fwrite(STDIO_FILE file, List#(t_DATA) args);
        do_write(STDIO_REQ_FWRITE, file, ?, args);
    endmethod


    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
        do_write(STDIO_REQ_FPRINTF, 0, msgID, args);
    endmethod

    method Action fprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID, List#(t_DATA) args);
        do_write(STDIO_REQ_FPRINTF, file, msgID, args);
    endmethod

    method Action vfprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID,
                           Vector#(STDIO_WRITE_MAX, t_DATA) data,
                           STDIO_NUM_DATA numData);
        let header = genHeader(STDIO_REQ_FPRINTF);
        header.fileHandle = file;
        header.text = msgID;
        header.numData = numData;

        newReqQ.enq(STDIO_REQ { data: data, header: header });
    endmethod

    method Action sprintf_req(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
        do_write(STDIO_REQ_SPRINTF, ?, msgID, args);
    endmethod

    method ActionValue#(GLOBAL_STRING_UID) sprintf_rsp() if (rspChain.first().operation == STDIO_RSP_SPRINTF);
        let str = unpack(rspChain.first().data);
        rspChain.deq();
        return str;
    endmethod

    method Action string_delete(GLOBAL_STRING_UID strID);
        let header = genHeader(STDIO_REQ_STRING_DELETE);
        header.text = strID;

        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod


    method Action fflush(STDIO_FILE file);
        let header = genHeader(STDIO_REQ_FFLUSH);
        header.fileHandle = file;

        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod

    method Action rewind(STDIO_FILE file);
        let header = genHeader(STDIO_REQ_REWIND);
        header.fileHandle = file;

        newReqQ.enq(STDIO_REQ { data: ?, header: header });
    endmethod


    method Action sync_req(Bool hostSync);
        let header = genHeader(STDIO_REQ_SYNC);
        // Signal with the low bit of the file handle
        header.fileHandle[0] = pack(hostSync);

        mar.enq(STDIO_REQ { data: ?, header: header });
    endmethod

    method Action sync_rsp() if (rspChain.first().operation == STDIO_RSP_SYNC);
        rspChain.deq();
    endmethod

    method STDIO_REQ_RING_CHUNK cond_mask_update();
        return condMask;
    endmethod
endmodule


function Vector#(STDIO_WRITE_MAX, t_DATA) stdioListToVec(List#(t_DATA) args);
    Vector#(STDIO_WRITE_MAX, t_DATA) data = newVector();

    if (List::length(args) == 1)
    begin
        Vector#(1, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) == 2)
    begin
        Vector#(2, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) == 3)
    begin
        Vector#(3, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) == 4)
    begin
        Vector#(4, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) == 5)
    begin
        Vector#(5, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) == 6)
    begin
        Vector#(6, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) == 7)
    begin
        Vector#(7, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) == 8)
    begin
        Vector#(8, t_DATA) v = toVector(args);
        for (Integer i = 0; i < List::length(args); i = i + 1) data[i] = v[i];
    end
    else if (List::length(args) != 0)
    begin
        data = error("Too many arguments to STDIO fwrite/printf (" + integerToString(List::length(args)) + ")");
    end

    return data;
endfunction


//
// mkStdIO_Disabled --
//     NULL version of STDIO.
//
module [CONNECTED_MODULE] mkStdIO_Disabled
    // interface:
    (STDIO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ),
              Add#(a__, 32, TMul#(STDIO_WRITE_MAX, t_DATA_SZ)));

    FIFO#(Bool) fopenFIFO <- mkFIFO();
    FIFO#(Bool) popenFIFO <- mkFIFO();
    FIFOF#(Bool) freadFIFO <- mkFIFOF();
    FIFO#(Bool) sprintfFIFO <- mkFIFO();
    FIFO#(Bool) syncFIFO <- mkFIFO();

    method Action fopen_req(GLOBAL_STRING_UID nameID, GLOBAL_STRING_UID modeID);
        fopenFIFO.enq(?);
    endmethod

    method ActionValue#(STDIO_FILE) fopen_rsp();
        fopenFIFO.deq();
        return ?;
    endmethod

    method Action fclose(STDIO_FILE file);
    endmethod

    method Action popen_req(GLOBAL_STRING_UID nameID, Bool forRead);
        popenFIFO.enq(?);
    endmethod

    method ActionValue#(STDIO_FILE) popen_rsp();
        popenFIFO.deq();
        return ?;
    endmethod

    method Action pclose(STDIO_FILE file);
    endmethod

    method Action fread_req(STDIO_FILE file,
                            STDIO_NUM_READ_ELEMS#(t_DATA) nmemb) provisos(Bits#(t_DATA, t_DATA_SZ));
        freadFIFO.enq(?);
    endmethod

    method Action freadMax_req(STDIO_FILE file);
        freadFIFO.enq(?);
    endmethod

    method ActionValue#(Maybe#(t_DATA)) fread_rsp();
        freadFIFO.deq();
        return tagged Invalid;
    endmethod

    method Bit#(TLog#(TAdd#(1, STDIO_MAX_READS_IN_FLIGHT))) fread_numInFlight();
        return (freadFIFO.notEmpty ? 1 : 0);
    endmethod

    method Action fwrite(STDIO_FILE file, List#(t_DATA) args);
    endmethod

    method Action printf(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    endmethod

    method Action fprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID, List#(t_DATA) args);
    endmethod

    method Action vfprintf(STDIO_FILE file, GLOBAL_STRING_UID msgID,
                           Vector#(STDIO_WRITE_MAX, t_DATA) data,
                           STDIO_NUM_DATA numData);
    endmethod

    method Action sprintf_req(GLOBAL_STRING_UID msgID, List#(t_DATA) args);
        sprintfFIFO.enq(?);
    endmethod

    method ActionValue#(GLOBAL_STRING_UID) sprintf_rsp();
        sprintfFIFO.deq();
        return ?;
    endmethod

    method Action string_delete(GLOBAL_STRING_UID strID);
    endmethod

    method Action fflush(STDIO_FILE file);
    endmethod

    method Action rewind(STDIO_FILE file);
    endmethod

    method Action sync_req(Bool hostSync);
        syncFIFO.enq(?);
    endmethod

    method Action sync_rsp();
        syncFIFO.deq();
    endmethod

    method STDIO_RSP_RING_CHUNK cond_mask_update();
        return 0;
    endmethod
endmodule


// ========================================================================
//
//   Special-purpose marshaller for STDIO reads the request message header
//   in order to minimize transmission sizes.
//
// ========================================================================

interface STDIO_MARSHALLER#(type t_FIFO_DATA, type t_DATA);
    method Action enq(STDIO_REQ#(t_DATA) msg);
    method Action deq();
    method t_FIFO_DATA first();
    method Bool notFull();
    method Bool notEmpty();
    method Bool isLast();     // Last chunk from the original enqueued data
endinterface

module mkStdIOReqMarshaller
    // Interface:
    (STDIO_MARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ),
              Bits#(STDIO_REQ_HEADER, t_REQ_HEADER_SZ),
              Bits#(STDIO_REQ#(t_DATA), t_REQ_SZ),
              // Number of chunks to send a full message
              NumAlias#(n, MARSHALLER_MSG_LEN#(t_FIFO_DATA, STDIO_REQ#(t_DATA))),
              Div#(t_DATA_SZ, t_FIFO_DATA_SZ, t_CHUNKS_PER_DATA),
              Div#(t_FIFO_DATA_SZ, t_DATA_SZ, t_DATA_PER_CHUNK));

    Reg#(Vector#(n, t_FIFO_DATA)) buffer <- mkRegU();
    Reg#(Bit#(TAdd#(1, TLog#(n)))) count <- mkReg(0);
    Reg#(Bool) empty <- mkConfigReg(True);

    RWire#(STDIO_REQ#(t_DATA)) incomingData <- mkRWire();

    //
    // All the operations could be accomplished in methods, but Bluespec's
    // scheduler can't detect mutually that calls to enq() and deq() are
    // mutually exclusive when called in different module hierarchy levels.
    //

    (* fire_when_enabled, no_implicit_conditions *)
    rule incoming (empty &&& incomingData.wget() matches tagged Valid .msg);
        empty <= False;

        // Send only as much of the message as necessary.  Most messages
        // don't require the entire buffer.  Computing the true space is
        // made easier by the requirement that the data size be a power of 2.

        let hdr_cnt = valueOf(MARSHALLER_MSG_LEN#(t_FIFO_DATA, STDIO_REQ_HEADER));

        if (valueOf(t_FIFO_DATA_SZ) <= valueOf(t_DATA_SZ))
        begin
            // Data elements are larger than the marshaller's chunk size.
            Bit#(TAdd#(1, TLog#(n))) data_cnt = zeroExtendNP(msg.header.numData);

            data_cnt = data_cnt * fromInteger(valueOf(t_CHUNKS_PER_DATA));
            count <= fromInteger(hdr_cnt) + data_cnt;
        end
        else
        begin
            // Data elements are smaller than the marshaller's chunk size.
            Bit#(TAdd#(TLog#(t_DATA_PER_CHUNK), TAdd#(1, TLog#(n)))) data_cnt = zeroExtendNP(msg.header.numData);

            // Prepare to round up before division
            data_cnt = data_cnt + fromInteger(valueOf(TSub#(t_DATA_PER_CHUNK, 1)));
            // Divide by the number data elements per marshaller chunk
            data_cnt = data_cnt / fromInteger(valueOf(t_DATA_PER_CHUNK));

            count <= fromInteger(hdr_cnt) + truncateNP(data_cnt);
        end

        // Convert the message to a vector of the marshalled size.
        buffer <= toChunks(msg);
    endrule


    method Action enq(STDIO_REQ#(t_DATA) msg) if (empty);
        incomingData.wset(msg);
    endmethod

    method Action deq() if (! empty);
        t_FIFO_DATA dummy = ?;
        buffer <= shiftInAtN(buffer, dummy);

        empty <= (count == 1);
        count <= count - 1;
    endmethod

    method t_FIFO_DATA first() if (! empty);
        return buffer[0];
    endmethod

    method Bool notFull();
        return empty;
    endmethod

    method Bool notEmpty();
        return ! empty;
    endmethod

    method Bool isLast();
        return count == 1;
    endmethod
endmodule


// ========================================================================
//
//   Special-purpose demarshaller for STDIO copes with multiple possible
//   output sizes and a single ring message size.  The ring message
//   size may be either smaller or larger than the true data size,
//   depending on the configuration of a given STDIO node.  Furthermore,
//   a ring message may be only partially full.
//
// ========================================================================

interface STDIO_DEMARSHALLER#(type t_FIFO_DATA, type t_DATA);
    method Action enq(t_FIFO_DATA chunk,
                      MARSHALLER_NUM_CHUNKS#(t_DATA, t_FIFO_DATA) nValid)
        provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
                  Bits#(t_DATA, t_DATA_SZ));

    method Action deq();
    method t_DATA first();
    method Bool notFull();
    method Bool notEmpty();

    // Unusual for a demarshaller, but for some STDIO data sizes, the marshalling
    // container is larger than the value!
    method Bool isLast();    
endinterface

module mkStdIORspDemarshaller
    // Interface:
    (STDIO_DEMARSHALLER#(t_FIFO_DATA, t_DATA))
    provisos (Bits#(t_FIFO_DATA, t_FIFO_DATA_SZ),
              Bits#(t_DATA, t_DATA_SZ));
    
    if (valueOf(t_DATA_SZ) >= valueOf(t_FIFO_DATA_SZ))
    begin
        //
        // Traditional demarshaller: more than one input chunk per output datum.
        //

        DEMARSHALLER#(t_FIFO_DATA, t_DATA) dem <- mkSimpleDemarshaller();

        method Action enq(t_FIFO_DATA chunk,
                          MARSHALLER_NUM_CHUNKS#(t_DATA, t_FIFO_DATA) nValid) = dem.enq(chunk);
        method Action deq() = dem.deq;
        method t_DATA first() = dem.first;
        method Bool notFull() = dem.notFull;
        method Bool notEmpty() = dem.notEmpty;
        method Bool isLast() = True;
    end
    else
    begin
        //
        // A single chunk has multiple messages.  This is actually more like
        // a marshaller with t_DATA as the marshalled size and t_FIFO_DATA as
        // the unmarshalled message.
        //
        MARSHALLER_N#(t_DATA, t_FIFO_DATA) mar <- mkSimpleMarshallerN(True);

        method Action enq(t_FIFO_DATA chunk,
                          MARSHALLER_NUM_CHUNKS#(t_DATA, t_FIFO_DATA) nValid);
            mar.enq(chunk, nValid);
        endmethod

        method Action deq() = mar.deq;
        method t_DATA first() = mar.first;
        method Bool notFull() = mar.notFull;
        method Bool notEmpty() = mar.notEmpty;
        method Bool isLast() = mar.isLast;
    end
endmodule
