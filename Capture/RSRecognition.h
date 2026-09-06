#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>

static inline VNDetectBarcodesRequest *RSBarcodeRequest(void) {
    VNDetectBarcodesRequest *request = [VNDetectBarcodesRequest new];
    // Exercise the same revision as the target iOS 15 device.
    request.revision = VNDetectBarcodesRequestRevision2;
    return request;
}

static inline NSArray<NSString *> *RSRecognizedStrings(NSArray<VNObservation *> *observations, BOOL barcode) {
    NSMutableArray<NSString *> *strings = [NSMutableArray array];
    for (VNObservation *observation in observations) {
        NSString *text = nil;
        if (barcode && [observation isKindOfClass:VNBarcodeObservation.class])
            text = ((VNBarcodeObservation *)observation).payloadStringValue;
        else if (!barcode && [observation isKindOfClass:VNRecognizedTextObservation.class])
            text = [((VNRecognizedTextObservation *)observation) topCandidates:1].firstObject.string;
        if (text.length) [strings addObject:text];
    }
    return strings;
}

static inline NSArray<NSString *> *RSBarcodeStrings(CGImageRef image, NSArray<VNObservation *> *observations) {
    NSArray<NSString *> *strings = RSRecognizedStrings(observations, YES);
    if (strings.count || !image) return strings;
    // Vision revision 2 may return no observations for a valid QR. CoreImage is a native fallback.
    CIDetector *detector = [CIDetector detectorOfType:CIDetectorTypeQRCode context:nil
        options:@{CIDetectorAccuracy:CIDetectorAccuracyHigh}];
    NSMutableArray *result = [NSMutableArray array];
    for (CIQRCodeFeature *feature in [detector featuresInImage:[CIImage imageWithCGImage:image]])
        if (feature.messageString.length) [result addObject:feature.messageString];
    return result;
}
