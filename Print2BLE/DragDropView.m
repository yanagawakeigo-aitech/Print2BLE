//
//  DragDropView.m
//  Print2BLE
//
//  Created by Larry Bank
//  Copyright (c) 2021 BitBank Software Inc. All rights reserved.
//

#import "DragDropView.h"
#import "ViewController.h"

@implementation DragDropView


- (id)initWithFrame:(NSRect)frame{
    self = [super initWithFrame:frame];
    if (self) {
        [self registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeFileURL]];
    }
    return self;
}

// Storyboard/nib-loaded views are created via -initWithCoder:, which never
// calls -initWithFrame:, so a DragDropView placed in Interface Builder
// would silently never register for dragging without this. (This used to
// be worked around by layering a second, runtime-created DragDropView
// covering the whole window on top of everything -- which then had to
// fight for z-order against every button placed in the storyboard and
// ended up silently swallowing real mouse clicks meant for them.)
- (void)awakeFromNib {
    [super awakeFromNib];
    [self registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeFileURL]];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender{
    [self setNeedsDisplay: YES];
    return NSDragOperationGeneric;
}

- (void)draggingExited:(id <NSDraggingInfo>)sender{
    [self setNeedsDisplay: YES];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    [self setNeedsDisplay: YES];
    return YES;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSPasteboard *pboard = [sender draggingPasteboard];

    // For the storyboard-loaded root view, myVC isn't wired via an IBOutlet
    // (there's no outlet slot for it in the .storyboard); resolve it from
    // the window lazily instead, once the window/view-controller hierarchy
    // is guaranteed to exist.
    if (_myVC == nil && [self.window.contentViewController isKindOfClass:[ViewController class]]) {
        _myVC = (ViewController *)self.window.contentViewController;
    }

    if ( [[pboard types] containsObject:NSPasteboardTypeFileURL] ) {
        NSArray<Class> *classes = @[[NSURL class]];
        NSDictionary *options = @{};
        NSArray<NSURL*> *files = [pboard readObjectsForClasses:classes options:options];
        for (NSURL *url in files) {
            NSString *str = [url path];
            if (str != nil)
                [_myVC processFile: str];
        }
    }
    return YES;
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PrintFileNotification"
                                                        object:self userInfo:nil];
}

@end
