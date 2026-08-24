#import <Cocoa/Cocoa.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *output = [NSString stringWithUTF8String:argv[1]];
        NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(1024, 1024)];
        [image lockFocus];
        NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(64, 64, 896, 896) xRadius:210 yRadius:210];
        NSGradient *gradient = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithCalibratedRed:0.12 green:0.46 blue:0.98 alpha:1],
            [NSColor colorWithCalibratedRed:0.20 green:0.76 blue:0.80 alpha:1]
        ]];
        [gradient drawInBezierPath:background angle:-45];
        [[NSColor colorWithWhite:1 alpha:0.96] setStroke];
        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 70; path.lineCapStyle = NSLineCapStyleRound; path.lineJoinStyle = NSLineJoinStyleRound;
        [path moveToPoint:NSMakePoint(280, 700)]; [path lineToPoint:NSMakePoint(472, 700)];
        [path curveToPoint:NSMakePoint(650, 520) controlPoint1:NSMakePoint(580, 700) controlPoint2:NSMakePoint(650, 630)];
        [path lineToPoint:NSMakePoint(650, 330)]; [path stroke];
        NSBezierPath *arrow = [NSBezierPath bezierPath];
        arrow.lineWidth = 70; arrow.lineCapStyle = NSLineCapStyleRound; arrow.lineJoinStyle = NSLineJoinStyleRound;
        [arrow moveToPoint:NSMakePoint(520, 445)]; [arrow lineToPoint:NSMakePoint(650, 315)]; [arrow lineToPoint:NSMakePoint(780, 445)]; [arrow stroke];
        [image unlockFocus];
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:image.TIFFRepresentation];
        NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        [png writeToFile:output atomically:YES];
    }
    return 0;
}
