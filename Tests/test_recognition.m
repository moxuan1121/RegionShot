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

        VNDetectBarcodesRequest *request = RSBarcodeRequest();
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        NSError *error = nil;
        BOOL success = [handler performRequests:@[request] error:&error];
        assert(success && !error);

        assert([RSBarcodeStrings(cg, request.results) containsObject:payload]);
        assert([RSBarcodeStrings(cg, @[]) containsObject:payload]);
        assert([RSBarcodeWebURL(@"https://example.com/path?q=1").host isEqualToString:@"example.com"]);
        assert([RSBarcodeWebURL(@"www.example.com.cn/path").host isEqualToString:@"www.example.com.cn"]);
        assert([RSBarcodeWebURL(@"example.jp").host isEqualToString:@"example.jp"]);
        assert([RSBarcodeWebURL(@"example.co.jp/path").host isEqualToString:@"example.co.jp"]);
        assert(RSBarcodeWebURL(@"普通二维码文本") == nil);
        CGImageRelease(cg);
        puts("RegionShot real QR generation/recognition check passed");
    }
}
