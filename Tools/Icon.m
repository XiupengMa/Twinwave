#import <AppKit/AppKit.h>

static void wave(CGContextRef c, CGFloat y, const CGFloat color[3]) {
    CGContextSetRGBStrokeColor(c,color[0],color[1],color[2],1);
    CGContextSetLineCap(c,kCGLineCapRound);
    CGContextSetLineWidth(c,73);
    CGContextMoveToPoint(c,230, y-32);
    CGContextAddCurveToPoint(c,330,y-32,339,y+84,443,y+84);
    CGContextAddCurveToPoint(c,537,y+84,546,y-40,647,y-40);
    CGContextAddCurveToPoint(c,700,y-40,740,y-11,794,y+42);
    CGContextStrokePath(c);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        if (argc != 2) return 1;
        for (int base=16;base<=512;base*=2) {
            if (base == 64) continue;
            for (int scale=1;scale<=2;scale++) {
                int n = base*scale;
                CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                CGContextRef c = CGBitmapContextCreate(NULL,n,n,8,0,space,(CGBitmapInfo)kCGImageAlphaPremultipliedLast);
                CGContextScaleCTM(c,n/1024.,n/1024.);
                CGPathRef square = CGPathCreateWithRoundedRect(CGRectMake(70,70,884,884),200,200,NULL);
                CGContextAddPath(c,square); CGContextClip(c);
                CGFloat colors[] = {0.055,0.115,0.15,1, 0.09,0.24,0.265,1};
                CGGradientRef gradient = CGGradientCreateWithColorComponents(space,colors,NULL,2);
                CGContextDrawLinearGradient(c,gradient,CGPointMake(795,90),CGPointMake(230,950),3);
                wave(c,600,(CGFloat[]){0.49,0.97,0.81});
                wave(c,407,(CGFloat[]){0.64,0.70,1.00});
                CGImageRef image = CGBitmapContextCreateImage(c);
                NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:image];
                NSString *name = [NSString stringWithFormat:@"%s/icon_%dx%d%@.png",argv[1],base,base,scale==1 ? @"" : @"@2x"];
                if (![[rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:name atomically:YES]) return 2;
                CGImageRelease(image); CGGradientRelease(gradient); CGPathRelease(square);
                CGContextRelease(c); CGColorSpaceRelease(space);
            }
        }
    }
    return 0;
}
