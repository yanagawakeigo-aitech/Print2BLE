//
//  ViewController.h
//  Print2BLE
//
//  Created by Larry Bank
//  Copyright (c) 2021 BitBank Software Inc. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "DragDropView.h"
#import "MyBLE.h"

@interface ViewController : NSViewController

@property (nonatomic, retain) DragDropView *myview;
@property (nonatomic) NSString *filename;
@property (weak) IBOutlet NSImageView *myImage;
@property (weak) IBOutlet NSTextField *StatusLabel;
@property (nonatomic, strong) NSScrollView *previewScrollView;
@property (nonatomic, strong) NSTextView *textInputView;
@property (nonatomic, strong) NSTextField *fontSizeLabel;
@property (nonatomic) CGFloat textFontSize;

// Process a new file
- (void)processFile:(NSString *)path;
- (void)ditherFile:(NSNotification *) notification;
- (uint8_t *)DitherImage:(uint8_t*)pPixels width:(int)iWidth height:(int)iHeight;
- (void) printImage;
- (void)processBitmap:(NSBitmapImageRep *)bitmap;
- (void)paste:(id)sender;
- (void)setupScrollablePreview;
- (void)setupTextEntryPanel;
- (NSBitmapImageRep *)bitmapFromText:(NSString *)text;
- (IBAction)PastePushed:(id)sender;
- (IBAction)PrintTextPushed:(id)sender;
- (IBAction)PreviewTextPushed:(id)sender;
- (IBAction)DecreaseFontSizePushed:(id)sender;
- (IBAction)IncreaseFontSizePushed:(id)sender;
@end

