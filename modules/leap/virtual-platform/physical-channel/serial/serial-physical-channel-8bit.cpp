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

#include <stdio.h>
#include <unistd.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sys/signal.h>
#include <sys/ioctl.h>
#include <signal.h>
#include <string.h>
#include <iostream>
#include <termios.h>
#include <errno.h>
#include <fcntl.h>

#include "SerialStream.h"
#include "SerialStreamBuf.h"
#include "SerialPort.h"

#include "awb/provides/physical_channel.h"
#include "awb/provides/serial_device_ucf.h"
#include "awb/provides/umf.h"

using namespace std;






void intializePort(LibSerial::SerialStream *serial_port, FILE *errfd) {
 // Configure the serial port
  serial_port->Open( "/dev/ttyS0" ) ;
   
  if ( ! serial_port->good() ) 
  {
     fprintf(errfd,"Error: Could not open serial port.\n");
     exit(1) ;
  }

    //
    // Set the baud rate of the serial port.
    //
    serial_port->SetBaudRate( LibSerial::SerialStreamBuf::BAUD_115200 ) ;
    if ( ! serial_port->good() ) 
    {
      fprintf(errfd,"Error: Could not open set baud rate.\n");
        exit(1) ;
    }
    //
    // Set the number of data bits.
    //
    serial_port->SetCharSize(  LibSerial::SerialStreamBuf::CHAR_SIZE_8 ) ;
    if ( ! serial_port->good() ) 
    {
      fprintf(errfd,"Error: Could not open set char size.\n");
      exit(1) ;
    }
    //
    // Disable parity.
    //
    serial_port->SetParity(  LibSerial::SerialStreamBuf::PARITY_ODD ) ;
    if ( ! serial_port->good() ) 
    {
      fprintf(errfd,"Error: Could not open set parity.\n");
        exit(1) ;
    }
    //
    // Set the number of stop bits.
    //
    serial_port->SetNumOfStopBits( 1 ) ;
    if ( ! serial_port->good() ) 
    {
      fprintf(errfd,"Error: Could not open set stop bite.\n");
      exit(1) ;
    }
    //
    // Adjust flow control.
    //
    if( HW_FLOW_CONTROL ) {
        serial_port->SetFlowControl(  LibSerial::SerialStreamBuf::FLOW_CONTROL_HARD ) ;
    } else {
        serial_port->SetFlowControl(  LibSerial::SerialStreamBuf::FLOW_CONTROL_NONE ) ;
    }

    if ( ! serial_port->good() ) 
    {
        fprintf(errfd,"Error: Could not open set HW Flow Control.\n");
        exit(1) ;
    }
    //
    // Do not skip whitespace characters while reading from the
    // serial port.
    //

    serial_port->unsetf( std::ios_base::skipws ) ;

}

// ==============================================
//            WARNING WARNING WARNING
// This code is swarming with potential deadlocks
// ==============================================

// ============================================
//               Physical Channel              
// ============================================

// constructor: set up hardware partition
PHYSICAL_CHANNEL_CLASS::PHYSICAL_CHANNEL_CLASS(
    PLATFORMS_MODULE p,
    PHYSICAL_DEVICES d) :
    PLATFORMS_MODULE_CLASS(p)
{
  incomingMessage = NULL;

  // open serial device. As it's non-blocking we should hold until we
  // have a physical connection
  errfd = fopen("./error_messages", "w");

  serial_port = new LibSerial::SerialStream();

  msg_count_in = 0; 

  msg_count_out = 0; 

  intializePort(serial_port, errfd);

  // Do some handshaking. We should probably bail out by re-running the fpga programming step. or something like
  // that

  int pos = 0; UMF_CHUNK v; 
  volatile int i =0 ;
  unsigned char* vptr = (unsigned char *) &v;

  //scheme is pos 0 0xDEADBEEF HW -> SW
  //          pos 1 0x0505CAFE SW -> HW
  //          pos 2 0x08675309 HW -> SW

  char password[4] = {'a','b','c','d'};
  char counterword[4] = {'A','B','C','D'};
  int ptr  = 0;
  int failures = 0;
  int retry  = 0;



  while(1){
    char recvchar=0, sendchar=0;     
  
    if(failures > 3000) {
      fprintf(errfd,"Failed too many times, try a reset\r\n");
      if(retry > 100) {
        fprintf(errfd,"Retried too many times, bailing\r\n"); 
        fflush(errfd);
        exit(1);
      }
      retry++;
      failures = 0;
      serial_port->Close();
      intializePort(serial_port, errfd);
    }

    if(serial_hasdata() > 0) {
      fprintf(errfd,"Has Data: %d\r\n",serial_hasdata());
      //serial_port->read((char *)&recvchar,1);
      serial_port->get(recvchar);
    } else {
      usleep(100); // sleep for a bit
      failures++;
      continue;
    }


    // if match move on
    if (password[ptr] == recvchar){
      sendchar = counterword[ptr];
      serial_port->write((const char *) &sendchar,1);
      ptr++;
      fprintf(errfd,"Loop: %d, send:%x recv:%x\r\n", failures, sendchar, recvchar);
    }
    // drain left overs 
    else if(password[0] == recvchar) {
	// Do nothing 
    }
    //something unexpected 
    //Write a junk character to reset the ublaze and try again
    else { 
      sendchar = 'X';
      serial_port->write((const char *)&sendchar,1);
      failures ++;
      ptr = 0; 
      fprintf(errfd,"Loop: %d, send:%x recv:%x\r\n", failures, (unsigned int)sendchar, (unsigned int)recvchar);
      // flush buffer
      while(serial_hasdata() > 0) {
        serial_port->get(recvchar);
      }
    }
    
    if(ptr == 4) {
      break;
    }

    
  }

   fprintf(errfd,"Sunk\r\n");

}

// destructor
PHYSICAL_CHANNEL_CLASS::~PHYSICAL_CHANNEL_CLASS()
{
  serial_port->Close();
}

// blocking read
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::Read(){
  // blocking loop
  fprintf(errfd,"In read\n");    
  while (true){
    // check if message is ready
    if (incomingMessage && !incomingMessage->CanAppend()) {
      // message is ready!
      UMF_MESSAGE msg = incomingMessage;
      incomingMessage = NULL;
      return msg;
    }
    // block-read data from pipe
    readPipe();
  }

  // shouldn't be here
  return NULL;
}

// non-blocking read
UMF_MESSAGE
PHYSICAL_CHANNEL_CLASS::TryRead(){   
 // We must check if there's new data. This will give us more and stop if we're full.

  if(serial_hasdata() > 0) {
    readPipe();
  }
  // now see if we have a complete message
  if (incomingMessage && !incomingMessage->CanAppend()){
    UMF_MESSAGE msg = incomingMessage;
    incomingMessage = NULL;
    return msg;
  }
  
  // message not yet ready
  return NULL;
}

// write
void
PHYSICAL_CHANNEL_CLASS::Write(UMF_MESSAGE message){
  // construct header
  unsigned char header[UMF_CHUNK_BYTES];
  message->EncodeHeader(header);

  msg_count_out++;
  fprintf(errfd,"attempting to write msg %d of length %d: %x\n", msg_count_out,message->GetLength(),*header);    
  //write header to pipe
  serial_port->write((const char *)header, UMF_CHUNK_BYTES);

  // write message data to pipe
  // NOTE: hardware demarshaller expects chunk pattern to start from most
  //       significant chunk and end at least significant chunk, so we will
  //       send chunks in reverse order
  message->StartReverseExtract();
  while (message->CanReverseExtract()){
    UMF_CHUNK chunk = message->ReverseExtractChunk();
    fprintf(errfd,"attempting to write %x\n",chunk);    
    serial_port->write((const char*)&chunk, sizeof(UMF_CHUNK));
  }

  // de-allocate message
  delete message;
  fflush(errfd);
}

//=========================================================================================

void
PHYSICAL_CHANNEL_CLASS::readPipe(){
  // determine if we are starting a new message
  fprintf(errfd, "entering readPipe\n");
  fflush(errfd);
  if (incomingMessage == NULL)    {
    // new message: read header
    unsigned char header[UMF_CHUNK_BYTES];
    // If we have no data to beginwith, bail.
    if(serial_hasdata() == 0) { 
      return;
    }

    msg_count_in++;
    fprintf(errfd, "readPipe forming header: %d\n", msg_count_in);

    for(int i = 0; i <  UMF_CHUNK_BYTES; i++) {
      while(serial_hasdata() == 0) {} // Block :(
      char temp;
      serial_port->get(temp);
      header[i] = temp;
      fprintf(errfd, "readPipe header[%d]: %x\n",i,temp);
    }

    // create a new message
    incomingMessage = new UMF_MESSAGE_CLASS;
    incomingMessage->DecodeHeader(header);
  }
  else if (!incomingMessage->CanAppend()){
    // uh-oh.. we already have a full message, but it hasn't been
    // asked for yet. We will simply not read the pipe, but in
    // future, we might want to include a read buffer.
  }
  else {
    // read in some more bytes for the current message
    // we will read exactly one chunk
    unsigned char buf[UMF_CHUNK_BYTES]; 
    int bytes_requested = UMF_CHUNK_BYTES;
    for(int i = 0; i <  UMF_CHUNK_BYTES; i++) {
      while(serial_hasdata() == 0) {} // Block :(
      char temp;
      serial_port->get(temp);
      buf[i] = temp;

    }

    fprintf(errfd, "readPipe chunk: %x\n",*((int*)buf));
    

    // This is not correct, perhaps
    if (incomingMessage->BytesUnwritten() < UMF_CHUNK_BYTES){
      bytes_requested = incomingMessage->BytesUnwritten();
    }

    // append read bytes into message
    incomingMessage->AppendBytes(bytes_requested, buf);
  }
  fprintf(errfd,"exiting readPipe\n");
  fflush(errfd);
}

int
PHYSICAL_CHANNEL_CLASS::serial_hasdata()
{
  return serial_port->rdbuf()->in_avail();
}
