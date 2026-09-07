#include <assert.h>
#include "../Capture/RSCaptureSymbol.h"

#ifndef LEGACY_ONLY
void *_UICreateScreenUIImage(void) { return (void *)1; }
#endif
void *UICreateScreenUIImage(void) { return (void *)2; }

int main(void) {
    void *(*capture)(void) = RSResolveCaptureSymbol();
    assert(capture);
#ifdef LEGACY_ONLY
    assert(capture() == (void *)2);
#else
    assert(capture() == (void *)1);
#endif
    return 0;
}
