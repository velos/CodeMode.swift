#ifndef CCODEMODE_JSC_H
#define CCODEMODE_JSC_H

#include <JavaScriptCore/JavaScriptCore.h>
#include <stdbool.h>

/// Mirrors JavaScriptCore's JSShouldTerminateCallback (declared in the private
/// JSContextRefPrivate.h). Returning true terminates the executing script.
typedef bool (*CCodeModeShouldTerminateCallback)(JSContextRef ctx, void *userData);

/// Installs a JavaScriptCore execution time limit on a context group.
///
/// `JSContextGroupSetExecutionTimeLimit` / `JSContextGroupClearExecutionTimeLimit`
/// are exported by the JavaScriptCore dynamic library but declared only in
/// WebKit's private `JSContextRefPrivate.h`, which the public SDK module does
/// not vend. This shim re-declares the two symbols so Swift can call them
/// without the private header. JavaScriptCore invokes `callback` roughly every
/// `limitSeconds` of script CPU time; returning true terminates the script.
void ccodemode_set_execution_time_limit(JSContextGroupRef group,
                                        double limitSeconds,
                                        CCodeModeShouldTerminateCallback callback,
                                        void *userData);

/// Clears any execution time limit previously installed on the group.
void ccodemode_clear_execution_time_limit(JSContextGroupRef group);

#endif /* CCODEMODE_JSC_H */
