import ModuleContext::*;

`include "asim/provides/virtual_platform.bsh"
`include "asim/provides/soft_connections_alg.bsh"
`include "asim/provides/soft_services_lib.bsh"
`include "asim/provides/soft_services_deps.bsh"
`include "asim/provides/soft_services.bsh"
`include "asim/provides/soft_connections.bsh"
`include "asim/provides/platform_services.bsh"
`include "asim/provides/connected_application.bsh"

// mkWrappedApplication

// A wrapper which instantiates the Soft Platform Interface and 
// the application. All soft connections are connected above.

module [SOFT_SERVICES_MODULE] mkWrappedApplication#(VIRTUAL_PLATFORM vp)
    // interface:
        ();
    
    let spi <- mkPlatformServices(vp);
    let app <- mkConnectedApplication();

endmodule

// mkApplicationEnv

// The actual application env instantiates the wrapper.

module [Module] mkApplicationEnv#(VIRTUAL_PLATFORM vp)
    // interface:
        ();
    
    // Instantiate the wrapper and connect all soft connections.
    // Dangling connections are errors.
    instantiateWithConnections(mkWrappedApplication(vp));

endmodule
