//
//  ViewController.m
//  Print2BLE
//
//  Created by Larry Bank
//  Copyright (c) 2021 BitBank Software Inc. All rights reserved.
//

#import "ViewController.h"
#import "MyBLE.h"

MyBLE *BLEClass;
uint8_t contrast_lookup[256];
static uint8_t *pDithered = NULL; // Dithered image data ready to print
static int iWidth, iHeight; // size of the image that's ready to print

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    _myview = [DragDropView alloc];
    _textFontSize = 24.0;
    [self setupScrollablePreview];
}

//
// Wrap the storyboard's fixed-size preview image view in a scroll view so
// that a preview taller than the visible area (e.g. a long pasted text)
// can be scrolled instead of running off the bottom of the window.
//
- (void)setupScrollablePreview
{
    NSView *parent = _myImage.superview;
    NSRect frame = _myImage.frame;
    if (parent == nil || [parent isKindOfClass:[NSScrollView class]]) return; // already set up

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:frame];
    scrollView.autoresizingMask = _myImage.autoresizingMask;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSBezelBorder;
    scrollView.drawsBackground = YES;

    [_myImage removeFromSuperview];
    _myImage.imageScaling = NSImageScaleAxesIndependently;
    _myImage.frame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
    _myImage.autoresizingMask = NSViewWidthSizable;

    scrollView.documentView = _myImage;
    [parent addSubview:scrollView];
    _previewScrollView = scrollView;
} /* setupScrollablePreview */

- (void)viewDidLayout {
    // viewDidLayout can fire many times (window resize, adding subviews, etc).
    // Everything below must run exactly once: re-adding the full-window
    // drag/drop overlay on every pass would push it back in front of the
    // button/text controls added after it, silently eating their clicks;
    // re-creating BLEClass and re-registering the notification observers
    // would also duplicate work and lose connection state.
    if (_didFinishLayoutSetup) return;
    _didFinishLayoutSetup = YES;

    // the outer frame size is known here, so set our drag/drop frame to the same size
    [_myview initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    // Do any additional setup after loading the view.
    BLEClass = [[MyBLE alloc] init];

    _myview.myVC = self; // give DragDropView access to our methods
    [[self view] addSubview:_myview];

    // Add the text-entry panel AFTER the full-window drag/drop overlay so
    // its controls sit in front of it and remain clickable/typeable.
    [self setupTextEntryPanel];
    [self setupDevicePicker];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(ditherFile:)
                                                 name:@"PrintFileNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(statusChanged:)
                                                 name:@"StatusChangedNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(bleStateMessage:)
                                                 name:@"BLEStateMessageNotification"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(refreshDeviceList:)
                                                 name:@"BLEDeviceListChangedNotification"
                                               object:nil];

//    [BLEClass startScan]; // scan and connect to any printers in the area

}
- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}
- (IBAction)FeedPushed:(NSButton *)sender {
    NSLog(@"Feed!");
    [BLEClass feedPaper];
}
- (IBAction)ConnectPushed:(NSButton *)sender {
    NSLog(@"Connect!");
    if (![BLEClass isConnected]) {
        _StatusLabel.stringValue = @"スキャン中...";
    }
    [BLEClass startScan];
}

- (IBAction)TransmitPushed:(NSButton *)sender {
    NSLog(@"Print!");
    [self printImage];
}

// Process a new file
- (void)processFile:(NSString *)path
{
    _filename = [[NSString alloc] initWithString:path];
    NSLog(@"User dropped file %@", _filename);

} /* processFile */

- (uint8_t *)DitherImage:(uint8_t*)pPixels width:(int)iWidth height:(int)iHeight
{
    int x, y, xmask=0, iDestPitch=0;
    int32_t cNew, lFErr, v=0, h;
    int32_t e1,e2,e3,e4;
    uint8_t cOut; // forward errors for gray
    uint8_t *pSrc, *pDest, *errors, *pErrors=NULL, *d, *s; // destination 8bpp image
    uint8_t pixelmask=0, shift=0;
    uint8_t ucTemp[640];
    
        errors = ucTemp; // plenty of space here for the bitmaps we'll generate
        memset(ucTemp, 0, sizeof(ucTemp));
        pSrc = pPixels; // write the new pixels over the original
        iDestPitch = (iWidth+7)/8;
        pDest = (uint8_t *)malloc(iDestPitch * iHeight);
        pixelmask = 0x80;
        shift = 1;
        xmask = 7;
        for (y=0; y<iHeight; y++)
        {
            s = &pSrc[y * iWidth];
            d = &pDest[y * iDestPitch];
            pErrors = &errors[1]; // point to second pixel to avoid boundary check
            lFErr = 0;
            cOut = 0;
            for (x=0; x<iWidth; x++)
            {
                cNew = *s++; // get grayscale uint8_t pixel
                cNew = (cNew * 2)/3; // make white end of spectrum less "blown out"
                // add forward error
                cNew += lFErr;
                if (cNew > 255) cNew = 255;     // clip to uint8_t
                cOut <<= shift;                 // pack new pixels into a byte
                cOut |= (cNew >> (8-shift));    // keep top N bits
                if ((x & xmask) == xmask)       // store it when the byte is full
                {
                    *d++ = ~cOut; // color is inverted
                    cOut = 0;
                }
                // calculate the Floyd-Steinberg error for this pixel
                v = cNew - (cNew & pixelmask); // new error for N-bit gray output (always positive)
                h = v >> 1;
                e1 = (7*h)>>3;  // 7/16
                e2 = h - e1;  // 1/16
                e3 = (5*h) >> 3;   // 5/16
                e4 = h - e3;  // 3/16
                // distribute error to neighbors
                lFErr = e1 + pErrors[1];
                pErrors[1] = (uint8_t)e2;
                pErrors[0] += e3;
                pErrors[-1] += e4;
                pErrors++;
            } // for x
        } // for y
    return pDest;
} /* DitherImage */

//
// Send the image that was previously dithered
// to the connected printer
//
- (void)printImage
{
    if (pDithered == NULL) {
        NSLog(@"printImage: nothing to print yet (drop an image or render some text first)");
        [self showAlertWithTitle:@"印刷するデータがありません" message:@"画像をドラッグ&ドロップするか、テキストを入力して「プレビュー更新」または「このテキストを印刷」を押してください。"];
        return; // no image to print
    }
    if (![BLEClass isConnected]) {
        NSLog(@"printImage: not connected to a printer");
        [self showAlertWithTitle:@"プリンターに接続されていません" message:@"「Connect」ボタンを押し、対応するBLEプリンターの電源とBluetoothがオンになっていることを確認してから、もう一度お試しください。"];
        return;
    }
    // Now send it to the printer
    [BLEClass preGraphics:iHeight];
    int iPitch = iWidth/8;
    uint8_t *pSrc = pDithered;
    for (int y=0; y<iHeight; y++) {
        [BLEClass scanLine:pSrc withLength:iPitch];
        pSrc += iPitch;
    }
    [BLEClass postGraphics];

} /* printImage */

- (void)statusChanged:(NSNotification *) notification
{
    if ([BLEClass isConnected]) {
        _StatusLabel.stringValue = [NSString stringWithFormat:@"Connected to: %@", [BLEClass getName]];
    } else {
        _StatusLabel.stringValue = @"Disconnected";
    }
} /* statusChanged */

// Bluetooth isn't in a scannable state (off, unauthorized, unsupported) or
// just finished powering on. Surface it in the status label so pressing
// Connect isn't silently a no-op with no explanation.
- (void)bleStateMessage:(NSNotification *) notification
{
    NSString *msg = notification.userInfo[@"message"];
    if (msg) {
        _StatusLabel.stringValue = msg;
    }
} /* bleStateMessage */

- (void)ditherFile:(NSNotification *) notification
{
    // load the file into an image object
    NSData *theFileData = [[NSData alloc] initWithContentsOfFile:_filename options: NSDataReadingMappedAlways error: nil]; // read file into memory
    if (theFileData) {
        // decode the image into a bitmap
        NSBitmapImageRep *bitmap = [[NSBitmapImageRep alloc] initWithData:theFileData];
        if (bitmap) {
            [self processBitmap:bitmap];
        }
    }
} /* ditherFile*/

//
// Render clipboard text into a bitmap and feed it through the same
// dither + preview pipeline used for dropped image files.
// Wired to Cmd+V / Edit > Paste via the standard NSResponder paste: action.
//
- (void)paste:(id)sender
{
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSString *text = [pboard stringForType:NSPasteboardTypeString];
    if (text == nil || text.length == 0) {
        NSLog(@"Paste: no text found on the clipboard");
        return;
    }
    NSBitmapImageRep *bitmap = [self bitmapFromText:text];
    if (bitmap) {
        [self processBitmap:bitmap];
    }
} /* paste */

//
// Rasterize a string of text (white background, black text) into a bitmap
// sized to the connected printer's width so it can be dithered like any
// other image.
//
- (NSBitmapImageRep *)bitmapFromText:(NSString *)text
{
    int printerWidth = [BLEClass getWidth];
    if (printerWidth <= 0) printerWidth = 384; // default width if not yet connected

    const CGFloat margin = 2.0; // keep just enough to avoid clipping glyph edges
    CGFloat fontSize = _textFontSize > 0 ? _textFontSize : 24.0;
    NSFont *font = [NSFont fontWithName:@"Menlo" size:fontSize];
    if (font == nil) font = [NSFont systemFontOfSize:fontSize];

    NSMutableParagraphStyle *paraStyle = [[NSMutableParagraphStyle alloc] init];
    paraStyle.lineBreakMode = NSLineBreakByWordWrapping;
    NSDictionary *attrs = @{ NSFontAttributeName: font,
                             NSForegroundColorAttributeName: [NSColor blackColor],
                             NSParagraphStyleAttributeName: paraStyle };

    CGFloat textWidth = printerWidth - (margin * 2);
    NSStringDrawingOptions drawOptions = NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading;
    NSRect boundingRect = [text boundingRectWithSize:NSMakeSize(textWidth, CGFLOAT_MAX)
                                              options:drawOptions
                                           attributes:attrs];
    int textHeight = (int)ceil(boundingRect.size.height + (margin * 2));
    if (textHeight < 1) textHeight = 1;

    NSSize imageSize = NSMakeSize(printerWidth, textHeight);
    NSImage *image = [[NSImage alloc] initWithSize:imageSize];
    [image lockFocus];
    [[NSColor whiteColor] setFill];
    NSRectFill(NSMakeRect(0, 0, imageSize.width, imageSize.height));
    NSRect drawRect = NSMakeRect(margin, margin, textWidth, boundingRect.size.height);
    [text drawWithRect:drawRect options:drawOptions attributes:attrs];
    [image unlockFocus];

    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
    return rep;
} /* bitmapFromText */

//
// Shared pipeline: resize to printer width, convert to grayscale, dither
// to 1-bpp, store it ready to print and update the preview image.
// Used for both dropped image files and rasterized clipboard text.
//
- (void)processBitmap:(NSBitmapImageRep *)bitmap
{
    if (bitmap) {
        {
            // convert to grayscale
            NSColorSpace *targetColorSpace = [NSColorSpace genericGrayColorSpace];
            NSBitmapImageRep *grayBitmap = [bitmap bitmapImageRepByConvertingToColorSpace: targetColorSpace renderingIntent: NSColorRenderingIntentDefault];
                                           
            int iOriginalWidth, iOriginalHeight;
            // scale to correct size (576 or 384 pixels wide)
            float ratio;
            iOriginalWidth = bitmap.size.width;
            iOriginalHeight = bitmap.size.height;
            iWidth = [BLEClass getWidth]; // get printer width in pixels
            if (iWidth <= 0) iWidth = 384; // default width if not yet connected to a printer
            ratio = (float)iOriginalWidth / (float)iWidth;
            iHeight = (int)((float)iOriginalHeight / ratio);
            NSSize newSize;
            newSize.width = iWidth;
            newSize.height = iHeight;
            // now resize it
            NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                      initWithBitmapDataPlanes:NULL
                                    pixelsWide:newSize.width
                                    pixelsHigh:newSize.height
                                 bitsPerSample:8
                               samplesPerPixel:1
                                      hasAlpha:NO
                                      isPlanar:NO
                                colorSpaceName:NSCalibratedWhiteColorSpace
                                   bytesPerRow:0
                                  bitsPerPixel:0];
            rep.size = newSize;
            [NSGraphicsContext saveGraphicsState];
            [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];
            [grayBitmap drawInRect:NSMakeRect(0, 0, newSize.width, newSize.height)];
            [NSGraphicsContext restoreGraphicsState];
            uint8_t *pPixels = [rep bitmapData];
            if (pDithered) free(pDithered);
            pDithered = [self DitherImage:pPixels width:iWidth height:iHeight];
            // Create a preview image
            // convert the 1-bpp image to 8-bit grayscale so that we can show it in the preview window
            uint8_t *pGray = (uint8_t *)malloc(iWidth * iHeight);
            int i, j, iCount;
            uint8_t c, ucMask, *s, *d;
            iCount = (iWidth/8) * iHeight;
            d = pGray;
            s = pDithered;
            for (i=0; i<iCount; i++) {
                ucMask = 0x80;
                c = *s++;
                for (j=0; j<8; j++) {
                    if (c & ucMask)
                        *d = 0;
                    else
                        *d = 0xff;
                    ucMask >>= 1;
                    d++;
                }
            }
            // make an NSImage out of the grayscale bitmap
            CGColorSpaceRef colorSpace;
            CGContextRef gtx;
            NSUInteger bitsPerComponent = 8;
            NSUInteger bytesPerRow = iWidth;
            colorSpace = CGColorSpaceCreateDeviceGray();
            gtx = CGBitmapContextCreate(pGray, iWidth, iHeight, bitsPerComponent, bytesPerRow, colorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaNone);
            CGImageRef myimage = CGBitmapContextCreateImage(gtx);
//            CGContextSetInterpolationQuality(gtx, kCGInterpolationNone);
            NSImage *image = [[NSImage alloc]initWithCGImage:myimage size:NSZeroSize];
            _myImage.image = image; // set it into the image view
            // Fit the preview to the scroll view's width and let it grow taller
            // than the visible area (rather than shrinking to fit), so long
            // previews (e.g. pasted text) can be scrolled instead of clipped.
            CGFloat previewWidth = _previewScrollView.contentSize.width;
            if (previewWidth <= 0) previewWidth = iWidth;
            CGFloat scale = previewWidth / (CGFloat)iWidth;
            CGFloat previewHeight = iHeight * scale;
            _myImage.frame = NSMakeRect(0, 0, previewWidth, previewHeight);
            [_myImage scrollPoint:NSMakePoint(0, previewHeight)]; // scroll to the top of the preview
            // Free temp objects
            CGColorSpaceRelease(colorSpace);
            CGContextRelease(gtx);
            CGImageRelease(myimage);
            free(pGray);
        }
    }
} /* processBitmap */

#pragma mark - Text entry panel

//
// Build a small panel at the bottom of the window: a multi-line text box,
// a Paste button (pulls the clipboard into the text box), a button to
// render+print the typed text, and +/- controls to adjust the font size
// used when rasterizing that text.
//
- (void)setupTextEntryPanel
{
    if (_textInputView != nil) return; // already set up

    NSView *parent = [self view];
    CGFloat winWidth = parent.frame.size.width; // 640 in the storyboard

    // Section label
    NSTextField *label = [NSTextField labelWithString:@"テキスト入力(貼り付け、または直接入力して印刷)"];
    label.frame = NSMakeRect(16, 122, winWidth - 32, 16);
    label.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    label.font = [NSFont systemFontOfSize:11];
    label.textColor = [NSColor secondaryLabelColor];
    [parent addSubview:label];

    // Multi-line text input, wrapped in its own scroll view
    NSRect textFrame = NSMakeRect(16, 16, 360, 96);
    NSScrollView *textScroll = [[NSScrollView alloc] initWithFrame:textFrame];
    textScroll.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    textScroll.hasVerticalScroller = YES;
    textScroll.borderType = NSBezelBorder;

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, textFrame.size.width, textFrame.size.height)];
    textView.minSize = NSMakeSize(0, textFrame.size.height);
    textView.maxSize = NSMakeSize(FLT_MAX, FLT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.textContainer.widthTracksTextView = YES;
    textView.font = [NSFont systemFontOfSize:13];
    textView.richText = NO;
    textScroll.documentView = textView;
    [parent addSubview:textScroll];
    _textInputView = textView;

    // Paste + Print buttons
    NSButton *pasteButton = [NSButton buttonWithTitle:@"貼り付け" target:self action:@selector(PastePushed:)];
    pasteButton.frame = NSMakeRect(386, 66, 90, 28);
    pasteButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [parent addSubview:pasteButton];

    NSButton *printTextButton = [NSButton buttonWithTitle:@"このテキストを印刷" target:self action:@selector(PrintTextPushed:)];
    printTextButton.frame = NSMakeRect(386, 32, 120, 28);
    printTextButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [parent addSubview:printTextButton];

    // Font size controls
    CGFloat fx = winWidth - 130; // right-aligned block
    NSTextField *fontLabel = [NSTextField labelWithString:@"文字サイズ"];
    fontLabel.frame = NSMakeRect(fx, 96, 120, 14);
    fontLabel.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    fontLabel.font = [NSFont systemFontOfSize:11];
    fontLabel.textColor = [NSColor secondaryLabelColor];
    [parent addSubview:fontLabel];

    NSButton *minusButton = [NSButton buttonWithTitle:@"－" target:self action:@selector(DecreaseFontSizePushed:)];
    minusButton.frame = NSMakeRect(fx, 66, 30, 28);
    minusButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [parent addSubview:minusButton];

    NSTextField *sizeLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"%dpt", (int)_textFontSize]];
    sizeLabel.frame = NSMakeRect(fx + 34, 66, 56, 28);
    sizeLabel.alignment = NSTextAlignmentCenter;
    sizeLabel.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [parent addSubview:sizeLabel];
    _fontSizeLabel = sizeLabel;

    NSButton *plusButton = [NSButton buttonWithTitle:@"＋" target:self action:@selector(IncreaseFontSizePushed:)];
    plusButton.frame = NSMakeRect(fx + 94, 66, 30, 28);
    plusButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [parent addSubview:plusButton];

    NSButton *previewButton = [NSButton buttonWithTitle:@"プレビュー更新" target:self action:@selector(PreviewTextPushed:)];
    previewButton.frame = NSMakeRect(fx, 32, 124, 28);
    previewButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [parent addSubview:previewButton];
} /* setupTextEntryPanel */

// Pull the current clipboard text into the text box (replacing its content).
- (IBAction)PastePushed:(id)sender
{
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSString *text = [pboard stringForType:NSPasteboardTypeString];
    if (text == nil) return;
    _textInputView.string = text;
} /* PastePushed */

// Render the typed text into the preview only (no printing).
- (IBAction)PreviewTextPushed:(id)sender
{
    NSString *text = _textInputView.string;
    if (text == nil || text.length == 0) return;
    NSBitmapImageRep *bitmap = [self bitmapFromText:text];
    if (bitmap) {
        [self processBitmap:bitmap];
    }
} /* PreviewTextPushed */

// Render the typed text and immediately send it to the connected printer.
- (IBAction)PrintTextPushed:(id)sender
{
    [self PreviewTextPushed:sender];
    [self printImage];
} /* PrintTextPushed */

- (void)updateFontSizeLabel
{
    _fontSizeLabel.stringValue = [NSString stringWithFormat:@"%dpt", (int)_textFontSize];
} /* updateFontSizeLabel */

- (IBAction)DecreaseFontSizePushed:(id)sender
{
    _textFontSize = MAX(8.0, _textFontSize - 2.0);
    [self updateFontSizeLabel];
    if (_textInputView.string.length > 0) [self PreviewTextPushed:sender];
} /* DecreaseFontSizePushed */

- (IBAction)IncreaseFontSizePushed:(id)sender
{
    _textFontSize = MIN(72.0, _textFontSize + 2.0);
    [self updateFontSizeLabel];
    if (_textInputView.string.length > 0) [self PreviewTextPushed:sender];
} /* IncreaseFontSizePushed */

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
} /* showAlertWithTitle:message: */

#pragma mark - Bluetooth device picker

//
// A dropdown of every BLE device seen during the current scan (not just
// ones that auto-matched a known printer name), plus a Disconnect button.
// This is the manual fallback for when auto-connect doesn't find/recognize
// a printer -- e.g. the PT210 needed its name added to findPrinter() before
// auto-connect could work at all, and any other unrecognized model would
// hit the same wall without a manual way around it.
//
- (void)setupDevicePicker
{
    if (_devicePopup != nil) return; // already set up
    NSView *parent = [self view];

    NSPopUpButton *popup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(32, 392, 350, 26) pullsDown:NO];
    [popup addItemWithTitle:@"検出したデバイス(スキャン待ち)"];
    popup.target = self;
    popup.action = @selector(DevicePopupChanged:);
    popup.autoresizingMask = NSViewMaxYMargin;
    [parent addSubview:popup];
    _devicePopup = popup;

    NSButton *disconnect = [NSButton buttonWithTitle:@"切断" target:self action:@selector(DisconnectPushed:)];
    disconnect.frame = NSMakeRect(390, 392, 70, 26);
    disconnect.autoresizingMask = NSViewMaxYMargin;
    [parent addSubview:disconnect];
    _disconnectButton = disconnect;
} /* setupDevicePicker */

// Rebuild the popup's contents whenever MyBLE finds a new device or clears
// its list (start of a fresh scan).
- (void)refreshDeviceList:(NSNotification *)notification
{
    NSArray<CBPeripheral *> *devices = [BLEClass foundPeripherals];
    NSString *previousTitle = _devicePopup.titleOfSelectedItem;
    [_devicePopup removeAllItems];
    if (devices.count == 0) {
        [_devicePopup addItemWithTitle:@"検出したデバイス(スキャン待ち)"];
        return;
    }
    for (CBPeripheral *peripheral in devices) {
        NSString *name = [peripheral name] ?: @"(名前なし)";
        [_devicePopup addItemWithTitle:name];
    }
    // Keep the previous selection if it's still in the list (e.g. after a
    // reconnect attempt), otherwise default to the newest device found.
    if (previousTitle && [_devicePopup itemWithTitle:previousTitle]) {
        [_devicePopup selectItemWithTitle:previousTitle];
    } else {
        [_devicePopup selectItemAtIndex:_devicePopup.numberOfItems - 1];
    }
} /* refreshDeviceList */

- (IBAction)DevicePopupChanged:(id)sender
{
    NSInteger index = _devicePopup.indexOfSelectedItem;
    NSArray<CBPeripheral *> *devices = [BLEClass foundPeripherals];
    if (index < 0 || index >= (NSInteger)devices.count) return; // "スキャン待ち" placeholder or stale index
    NSLog(@"Manually connecting to device at index %ld", (long)index);
    _StatusLabel.stringValue = @"接続中...";
    [BLEClass connectToDiscoveredPeripheralAtIndex:index];
} /* DevicePopupChanged */

- (IBAction)DisconnectPushed:(id)sender
{
    NSLog(@"Disconnect!");
    [BLEClass disconnectPrinter];
} /* DisconnectPushed */

@end
