#include "CCodeModeJSC.h"

// Declared in JavaScriptCore's private JSContextRefPrivate.h but exported from
// the JavaScriptCore dynamic library on every Apple platform. Re-declared here
// so the package can bind to them without depending on the private SDK header.
extern void JSContextGroupSetExecutionTimeLimit(JSContextGroupRef group,
                                                double limit,
                                                CCodeModeShouldTerminateCallback callback,
                                                void *userData);
extern void JSContextGroupClearExecutionTimeLimit(JSContextGroupRef group);

void ccodemode_set_execution_time_limit(JSContextGroupRef group,
                                        double limitSeconds,
                                        CCodeModeShouldTerminateCallback callback,
                                        void *userData) {
    JSContextGroupSetExecutionTimeLimit(group, limitSeconds, callback, userData);
}

void ccodemode_clear_execution_time_limit(JSContextGroupRef group) {
    JSContextGroupClearExecutionTimeLimit(group);
}
