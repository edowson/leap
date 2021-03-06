#ifndef __SIM_CHANNELIO__
#define __SIM_CHANNELIO__

#include <queue>
#include <pthread.h>

#include "platforms-module.h"
#include "awb/provides/umf.h"
#include "awb/provides/physical_platform.h"

using namespace std;

// ============================================
//       Base Class for Message Receivers
// ============================================

typedef class CIO_DELIVERY_STATION_CLASS* CIO_DELIVERY_STATION;
class CIO_DELIVERY_STATION_CLASS
{
    public:
        virtual void DeliverMessage(UMF_MESSAGE) = 0;
};

// ============================================
//             Channel I/O Station
// ============================================

enum CIO_STATION_TYPE
{
    CIO_STATION_TYPE_READ,
    CIO_STATION_TYPE_DELIVERY
};

struct CIO_STATION_INFO
{
    // type of reads the station does (read/delivery)
    CIO_STATION_TYPE        type;

    // link to module (only required for interrupt-type stations)
    CIO_DELIVERY_STATION    module;

    // buffers
    queue<UMF_MESSAGE>  readBuffer;
};

// ============================================
//                 Channel I/O                 
// ============================================

typedef class CHANNELIO_CLASS* CHANNELIO;
class CHANNELIO_CLASS:  public PLATFORMS_MODULE_CLASS
{

  private:


  public:

    CHANNELIO_CLASS(PLATFORMS_MODULE, PHYSICAL_DEVICES);
    ~CHANNELIO_CLASS();
    
    void        RegisterForDelivery(int, CIO_DELIVERY_STATION);
    UMF_MESSAGE TryRead(int);
    UMF_MESSAGE Read(int);
    void        Write(int, UMF_MESSAGE);
    void        Poll();

};

#endif
