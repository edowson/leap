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

`include "awb/provides/physical_platform.bsh"

interface CHANNEL_IO;
    method ActionValue#(Maybe#(Bit#(32)))   read();
    method Action                           write(Bit#(32) data);
    method ActionValue#(Bool)               isDestroyed();
endinterface

import "BDPI" function ActionValue#(Bit#(8))  cio_open(Bit#(8) programID);
import "BDPI" function ActionValue#(Bit#(32)) cio_read(Bit#(8) handle);
import "BDPI" function Action   cio_write(Bit#(8) handle, Bit#(32) data);
import "BDPI" function ActionValue#(Bit#(8))  cio_isdestroyed(Bit#(8) handle);

module mkChannelIO#(PHYSICAL_DRIVERS drivers) (CHANNEL_IO);

    Reg#(Bit#(8))   handle  <- mkReg(0);
    Reg#(Bit#(1))   ready   <- mkReg(0);

    rule initialize(ready == 0);
        Bit#(8) wire_out <- cio_open(0);
        handle <= wire_out;
        ready  <= 1;
    endrule

    method ActionValue#(Maybe#(Bit#(32))) read() if (ready == 1);
        // 0xFFFFFFFF means no data
        // The Unix channelio C module uses the MSB to indicate
        // absence of data on the pipe. We convert this to a
        // tagged union
        Bit#(32) data <- cio_read(handle);
        Maybe#(Bit#(32)) retval;
        if (data == 'hFFFFFFFF)
            retval = tagged Invalid;
        else
            retval = tagged Valid data;
        return retval;
    endmethod

    method Action write(Bit#(32) data) if (ready == 1);
        cio_write(handle, data);
    endmethod

    method ActionValue#(Bool) isDestroyed() if (ready == 1);
        Bit#(8) term <- cio_isdestroyed(handle);
        if (term == 0)
            return False;
        else
            return True;
    endmethod

endmodule