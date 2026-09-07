#include <dlfcn.h>

static inline void *RSResolveCaptureSymbol(void) {
    // Mach-O imports __UICreateScreenUIImage; dlsym omits only the ABI prefix.
    void *symbol = dlsym(RTLD_DEFAULT, "_UICreateScreenUIImage");
    return symbol ?: dlsym(RTLD_DEFAULT, "UICreateScreenUIImage");
}
