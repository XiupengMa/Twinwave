#import "Devices.h"

@interface TWCapture : NSObject
/// Configure and stop on one serial queue. The main thread may drain peaks concurrently.
- (NSString *)startDevice:(TWDevice *)device input:(BOOL)input;
- (void)stop;
- (float)takePeakWithData:(BOOL *)received;
@end
