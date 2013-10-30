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

import FIFO::*;
import Vector::*;

`include "awb/rrr/client_stub_ASSERTIONS.bsh"
`include "awb/rrr/service_ids.bsh"
`include "awb/dict/ASSERTIONS.bsh"


module [CONNECTED_MODULE] mkAssertionsService
    // interface:
        ();


    //***** State Elements *****
  
    // Communication link to the rest of the Assertion checkers
    Connection_Chain#(ASSERTION_DATA) chain <- mkConnection_Chain(`RINGID_ASSERTS);
  
    // Communication to our RRR server
    ClientStub_ASSERTIONS clientStub <- mkClientStub_ASSERTIONS();
  
    Reg#(Bit#(32)) fpgaCC <- mkReg(0);


    // ***** Rules *****
  
    rule countCC (True);
        fpgaCC <= fpgaCC + 1;
    endrule


    // processResp

    // Process the next response from an individual assertion checker.
    // Pass assertions on to software.  Here we let the software deal with
    // the relatively complicated base ID and assertions vector.

    rule processResp (True);
        let ast <- chain.recvFromPrev();
        clientStub.makeRequest_Assert(zeroExtend(pack(ast.baseID)),
                                      fpgaCC,
                                      zeroExtend(pack(ast.assertions)));
    endrule


endmodule
