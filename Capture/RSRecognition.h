#import <Vision/Vision.h>

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
