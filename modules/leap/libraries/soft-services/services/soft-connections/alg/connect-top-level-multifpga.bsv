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

import FIFOF::*;
import Clocks::*;
import ModuleContext::*;
import HList::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/physical_interconnect.bsh"
`include "awb/provides/soft_connections_common.bsh"
`include "awb/provides/soft_connections_alg.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"


// instatiateWithConnections
// Connect all remaining connections at the top-level. 
// This includes all one-to-many and many-to-one connections,
// and all shared interconnects.

// For backwards compatability we also still handle chains.
// Called at the top level, very similar to with connections now...
module finalizeSoftConnection#(LOGICAL_CONNECTION_INFO info) (Empty);

  Clock clk <- exposeCurrentClock();

  String errorStr = "";

  // Backwards compatability: Connect all chains in the resulting context.
  connectChains(info, clk); 

  // Connect all broadcasts in the resulting context.
  match {.unmatched_sends, .unmatched_recvs} <- connectMulticasts(clk, info);

  // Error out if there are dangling connections
  // however, "model" where this is called may be on another FPGA.  So, unmatched things 
  // are acceptable - the generated 
  Bool error_occurred = False;
  // Final Dangling sends
  for (Integer x = 0; x < List::length(unmatched_sends); x = x + 1)
  begin
    let cur = unmatched_sends[x];
    let cur_entry = ctHashValue(cur);
  
    // clear out leftovers from model top level 
    if(info.exposeAllConnections)
      begin
        // In this case we should display the unmatched connection
        printDanglingSend(x,cur);
	let newStr <- printSend(cur);
        errorStr = "Matched Send: " + newStr + errorStr;	
      end
    else if (!cur_entry.optional)
      begin
        messageM("ERROR: Unmatched logical send: ");
	let newStr <- printSend(cur);
        errorStr = "ERROR: Unmatched logical send " + integerToString(x) + ": " + newStr + "\n" + errorStr;	
        error_occurred = True;
      end
  end

  // Final Dangling recvs
  for (Integer x = 0; x < List::length(unmatched_recvs); x = x + 1)
  begin
    let cur = unmatched_recvs[x];
    let cur_entry = ctHashValue(cur);

    // clear out leftovers from model top level 
    if(info.exposeAllConnections)
      begin
        // In this case we should display the unmatched connection
        printDanglingRecv(x,cur);
	let newStr <- printRecv(cur);		 
        errorStr = "Matched Recv: " + newStr + errorStr; 
      end
    else if (!cur_entry.optional)
      begin
        messageM("ERROR: Unmatched logical receive: ");
	let newStr <- printRecv(cur);		 
        errorStr = "ERROR: Unmatched logical receive " + integerToString(x) + ": " + newStr + "\n" + errorStr; 
        error_occurred = True;
      end
  end

  // Emit the global string table
  printGlobStrings(info.globalStrings);

endmodule


// connectChains

// Backwards Compatability: Connection Chains

module connectChains#(LOGICAL_CONNECTION_INFO info, Clock c) ();

    let chains = info.chains;

    for (Integer x = 0; x < length(chains); x = x + 1)
      begin		
        // Iterate through the chains.
        let chn = chains[x];
        if(info.exposeAllConnections)
          begin
            printChain(x,chn);
          end
        else
          begin
            messageM("Closing Chain: [" + chn.logicalName + "]");
            connectOutToIn(chn.outgoing, chn.incoming, 0);
          end
      end
    
endmodule
