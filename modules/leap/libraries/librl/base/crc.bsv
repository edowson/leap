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

import Vector::*;


//
// CRCGEN --
//   Compute one round of CRC, consuming a chunk and updating the remainder.
//
interface CRCGEN#(numeric type t_REM_SZ, type t_CHUNK);
    method Bit#(t_REM_SZ) nextChunk(Bit#(t_REM_SZ) curCRC, t_CHUNK chunk);
endinterface


//
// Convert a Koopman-style polynomial into an MSB-first polynomial that is
// used by our code.  CRC polynomials have both the high and the bits always
// set and the only difference between the two is which bit is represented
// (and always 1).  MSB-first drops the high bit, Koopman drops the low bit.
//
function Bit#(t_SZ) koopmanPoly(Bit#(t_SZ) x) = (x << 1) | 1;

//
// mkAutoCRCGen --
//   Pick the right polynomial for the requested CRC size.
//
//   Many polynomials are chosen from Philip Koopman's papers, either:
//     Cyclic Redundancy Code (CRC) Polynomial Selection For Embedded Networks
//   or
//     32-Bit Cyclic Redundancy Codes for Internet Applications
//
module mkAutoCRCGen
    // Interface:
    (CRCGEN#(t_REM_SZ, t_CHUNK))
    provisos (Bits#(t_CHUNK, t_CHUNK_SZ),
              Add#(t_REM_SZ, n_OFFSET, t_CHUNK_SZ));

    CRCGEN#(t_REM_SZ, t_CHUNK) _c = ?;
    case (valueOf(t_REM_SZ))
         1: _c <- mkCRCGen('h1);                   // parity
         3: _c <- mkCRCGen(koopmanPoly('h5));
         4: _c <- mkCRCGen(koopmanPoly('h9));
         5: _c <- mkCRCGen(koopmanPoly('h12));
         6: _c <- mkCRCGen(koopmanPoly('h21));
         7: _c <- mkCRCGen(koopmanPoly('h48));
         8: _c <- mkCRCGen(koopmanPoly('ha6));
         9: _c <- mkCRCGen(koopmanPoly('h14b));
        10: _c <- mkCRCGen(koopmanPoly('h319));
        11: _c <- mkCRCGen(koopmanPoly('h583));
        12: _c <- mkCRCGen(koopmanPoly('hc07));
        13: _c <- mkCRCGen(koopmanPoly('h102a));
        14: _c <- mkCRCGen(koopmanPoly('h21e8));
        15: _c <- mkCRCGen(koopmanPoly('h4976));
        16: _c <- mkCRCGen(koopmanPoly('hbaad));
        17: _c <- mkCRCGen('h1685b);               // CAN
        21: _c <- mkCRCGen('h102899);              // CAN
        24: _c <- mkCRCGen('h864cfb);              // Radix-64
        30: _c <- mkCRCGen('h2030b9c7);            // CDMA
        32: _c <- mkCRCGen(koopmanPoly('hba0dc66b));
        40: _c <- mkCRCGen('h4820009);             // GSM
        64: _c <- mkCRCGen('h42f0e1eba9ea3693);    // ECMA

        default: error("No CRC polynomial defined for size " + integerToString(valueOf(t_REM_SZ)));
    endcase

    return _c;
endmodule


//
// mkCRCGen --
//   A CRC generator, with each round consuming one t_CHUNK and generating
//   a CRC of size t_REM_SZ.
//
//   The polynomial requested must correspond to the remainder size t_REM_SZ!
//   The polynomial bit order is the "normal" bit order, e.g. from the
//   table in http://en.wikipedia.org/wiki/Cyclic_redundancy_check.
//   For example, the polynomial for CRC-8-CCITT (ATM HEC) is 8'h7.
//
module mkCRCGen#(Bit#(t_REM_SZ) poly)
    // Interface:
    (CRCGEN#(t_REM_SZ, t_CHUNK))
    provisos (Bits#(t_CHUNK, t_CHUNK_SZ),
              // The chunk size must be >= the remainder size.
              Add#(t_REM_SZ, n_OFFSET, t_CHUNK_SZ));

    //
    // One step of the CRC.  Inject a single bit (bitIn) into the remainder.
    //
    function Bit#(t_REM_SZ) oneStep(Bit#(1) bitIn, Bit#(t_REM_SZ) rem);
        let multiple = ((bitIn ^ msb(rem)) == 1 ? poly : 0);
        return (rem << 1) ^ multiple;
    endfunction

    //
    // Pre-compute the bit masks that will turn the oneStep() above into a
    // simple set of XORs at run time.  This is accomplished by iterating
    // and generating the CRC with only a single bit set at each of the
    // input chunk positions.
    //
    Vector#(t_CHUNK_SZ, Vector#(t_REM_SZ, Bit#(1))) chunk_bit_masks = newVector();
    for (Integer c = 0; c < valueOf(t_CHUNK_SZ); c = c + 1)
    begin
        // Set only bit "c" in a chunk
        Vector#(t_CHUNK_SZ, Bit#(1)) bits_in = replicate(0);
        bits_in[c] = 1;

        // Compute the CRC of a chunk with just bit "c" set.
        chunk_bit_masks[c] = unpack(foldr(oneStep, 0, bits_in));
    end

    // The previous step computes an array indexed by chunks, with sub-arrays
    // of bit positions in the computed remainder.  What we really need is
    // an outer array indexed by bit position in the remainder.  For each
    // remainder bit we need a vector of bits in a chunk that are active
    // in the given remainder's bit position.  This is just the transposition
    // of chunk_bit_masks.
    Vector#(t_REM_SZ, Vector#(t_CHUNK_SZ, Bit#(1))) rem_bit_masks =
        transpose(chunk_bit_masks);

    //
    // Update CRC given curCRC and a new chunk.
    //
    method Bit#(t_REM_SZ) nextChunk(Bit#(t_REM_SZ) curCRC, t_CHUNK chunk);
        // Map curCRC and chunk to vectors of bits
        Vector#(t_CHUNK_SZ, Bit#(1)) chunk_bits = unpack(pack(chunk));
        Vector#(t_REM_SZ, Bit#(1)) curCRC_bits = unpack(pack(curCRC));

        //
        // The static steps during module construction have built rem_bit_masks,
        // a table of bit positions in "chunk" that must be XORed for each
        // resulting remainder bit position.
        //
        Bit#(t_REM_SZ) r = 0;
        for (Integer b = 0; b < valueOf(t_REM_SZ); b = b + 1)
        begin
            // Mask the bits relevant to remainder bit "b" by ANDing the
            // incoming chunk's bits with rem_bit_masks[b].
            let masked_chunk = map(uncurry(\& ), zip(chunk_bits, rem_bit_masks[b]));
            // XOR those relevant chunk bits, forming remainder bit "b".
            r[b] = foldr(\^ , 0, masked_chunk);

            // Include the existing (incoming) curCRC by performing the same
            // steps on it, and XORing into remainder bit "b".  The mask
            // is taken from the high bits of the same rem_bit_masks as the
            // previous step.
            let masked_cur_crc = map(uncurry(\& ),
                                     zip(curCRC_bits, takeTail(rem_bit_masks[b])));
            r[b] = foldr(\^ , r[b], masked_cur_crc);
        end

        return r;
    endmethod
endmodule
