#include <stdio.h>
#include <pthread.h>

#include "asim/syntax.h"
#include "awb/provides/virtual_platform.h"

#include "application-env-hybrid-soft-conn.h"

APPLICATION_ENV_CLASS::APPLICATION_ENV_CLASS(VIRTUAL_PLATFORM vp) : 
    app(new CONNECTED_APPLICATION_CLASS(vp))
{
    return;
}

void 
APPLICATION_ENV_CLASS::InitApp(int argc, char** argv)
{
    // TODO: pass argc, argv?
    app->Init();
    return;
}

int 
APPLICATION_ENV_CLASS::RunApp(int argc, char** argv)
{
    // TODO: pass argc, argv, get return value
    // return app->Main(argc, argv);
    app->Main();
    return 0;
}