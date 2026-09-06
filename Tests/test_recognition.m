#import "../Capture/RSRecognition.h"
#import <CoreImage/CoreImage.h>
#include <assert.h>

int main(void) {
    @autoreleasepool {
        NSString *payload = @"RegionShot-QR-check-2026";
        CIFilter *filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
        [filter setValue:[payload dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
        CIImage *qr = [filter.outputImage imageByApplyingTransform:CGAffineTransformMakeScale(8, 8)];
        CGRect bounds = CGRectInset(qr.extent, -32, -32);
        CIImage *white = [[CIImage imageWithColor:[CIColor colorWithRed:1 green:1 blue:1]] imageByCroppingToRect:bounds];
        CIImage *image = [qr imageByCompositingOverImage:white];
        CIContext *context = [CIContext contextWithOptions:nil];
        CGImageRef cg = [context createCGImage:image fromRect:bounds];
        assert(cg);
        VNDetectBarcodesRequest *request = [VNDetectBarcodesRequest new];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        NSError *error = nil;
        BOOL success = [handler performRequests:@[request] error:&error];
        if (!success) NSLog(@"Vision test failed: %@", error);
        assert(success && !error);
        assert([RSRecognizedStrings(request.results, YES) containsObject:payload]);
        assert(RSRecognizedStrings(request.results, NO).count == 0);
        CGImageRelease(cg);
        puts("RegionShot real QR generation/recognition check passed");
    }
}
