#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

static inline NSURL *RSBarcodeWebURL(NSString *text) {
    NSString *value = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!value.length) return nil;
    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:nil];
    NSTextCheckingResult *match = [detector firstMatchInString:value options:0 range:NSMakeRange(0, value.length)];
    if (!match || !NSEqualRanges(match.range, NSMakeRange(0, value.length))) return nil;
    NSString *scheme = match.URL.scheme.lowercaseString;
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"]) ? match.URL : nil;
}

static inline VNDetectBarcodesRequest *RSBarcodeRequest(void) {
    VNDetectBarcodesRequest *request = [VNDetectBarcodesRequest new];
    // Exercise the same revision as the target iOS 15 device.
    request.revision = VNDetectBarcodesRequestRevision2;
    return request;
}

static inline NSArray<NSString *> *RSBarcodePayloads(NSArray<VNObservation *> *observations) {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (VNObservation *observation in observations) {
        NSString *text = nil;
        if ( [observation isKindOfClass:VNBarcodeObservation.class])
            text = ((VNBarcodeObservation *)observation).payloadStringValue;
        if (text.length) [strings addObject:text];
    }
    return strings;
}

static inline NSArray<NSString *> *RSBarcodeStrings(CGImageRef image, NSArray<VNObservation *> *observations) {
    NSArray<NSString *> *strings = RSBarcodePayloads(observations);
    if (strings.count || !image) return strings;
    // Vision revision 2 may return no observations for a valid QR. CoreImage is a native fallback.
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
        options:@{CIDetectorAccuracy:CIDetectorAccuracyHigh}];
    NSMutableArray *result = [NSMutableArray array];
    for (CIQRCodeFeature *feature in [detector featuresInImage:[CIImage imageWithCGImage:image]])
        if (feature.messageString.length) [result addObject:feature.messageString];
    return result;
}
