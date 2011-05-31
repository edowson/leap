//
// Copyright (C) 2011 Intel Corporation
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

import List::*;
import ModuleContext::*;

`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_connections_common.bsh"

// Some kind soul (leap-connect) has already put the external metadata
// into the environment, so this file is empty.

/*
// Forwards-compatability
typedef Tuple4#(String, String, String, Integer) ConMap;

// some kind soul (leap-connect) has already put the external metadata
// into the environment


//Add the parsed information back is as normal connections

module [CONNECTED_MODULE]  addConnections#(WITH_SERVICES#(SOFT_SERVICES_INTERMEDIATE#(t_NUM_IN, t_NUM_OUT), t_IFC) mod, List#(ConMap) sends, List#(ConMap) recs) ();
  addConnectionsSC(extractWithConnections(mod),sends,recs);
endmodule


module [CONNECTED_MODULE] addConnectionsSC#(WITH_CONNECTIONS#(numIn, numOut) mod, Tuple2#(List#(ConMap), List#(ConMap)) con_map) ();
   
   match {.sends, .recvs} = con_map;

   // Add Sends
   let nSends = length(sends);
   for (Integer x = 0; x < nSends; x = x + 1)
   begin
     match {.nm, .contype, .platform, .idx} = sends[x];
     let inf = LOGICAL_SEND_INFO {logicalName: nm, logicalType: contype, optional: False, outgoing: mod.outgoing[idx], computePlatform: platform};
     registerSend(inf);
   end

   // Add Recvs
   let nRecvs = length(recvs);
   for (Integer x = 0; x < nRecvs; x = x + 1)
   begin 
     match {.nm, .contype, .platform, .idx} = recs[x];
     let inf = LOGICAL_RECV_INFO{logicalName:nm, logicalType: contype, optional: False, incoming: mod.incoming[idx], computePlatform: platform};
     registerRecv(inf);
   end
   
   // Add Chains
   for (Integer x = 0; x < valueof(CON_NUM_CHAINS); x = x + 1)
   begin
    // Collect up our info.
    let info = 
        LOGICAL_CHAIN_INFO 
        {
            logicalIdx: x, 
            logicalType: "", 
            incoming: mod.chains[x].incoming,
            outgoing: mod.chains[x].outgoing
        };

    // Register the chain
    registerChain(info);
   end

endmodule


   
module [CONNECTED_MODULE] buryContextSC#(WithConnections#(numIn, numOut) mod) ();   
   let ctxtIn <- getContext();
   let sends = ctxtIn.unmatchedSends;
   let recs  = ctxtIn.unmatchedRecvs;

   // ditch old, partial context after extracting the useful bit
   putContext(initializeContext());

   //Add Sends
   
   let nSends = length(sends);
   for (Integer x = 0; x < nSends; x = x + 1)
   begin
     match {.nm, .contype, .idx} = sends[x];
     let inf = LOGICAL_SEND_INFO {logicalName: sends[x].nm, logicalType: sends[x].contype, optional: False, oneToMany: False, outgoing: mod.outgoing[idx]};
     registerSend(inf);
   end

   //Add Recs

   let nRecs = length(recs);
   for (Integer x = 0; x < nRecs; x = x + 1)
   begin
     match {.nm, .contype, .idx} = recs[x];
     let inf = LOGICAL_RECV_INFO {logicalName:nm, logicalType: contype, optional: False, manyToOne: False, incoming: mod.incoming[idx]};
     registerRecv(inf);
   end
   
   //Add Chains
   for (Integer x = 0; x < valueof(CON_NUM_CHAINS); x = x + 1)
   begin
    // Collect up our info.
    let info = 
        LOGICAL_CHAIN_INFO 
        {
            logicalIdx: x, 
            logicalType: "", 
            incoming: mod.chains[x].incoming,
            outgoing: mod.chains[x].outgoing
        };

    // Register the chain
    registerChain(info);
   end


 
endmodule
*/
