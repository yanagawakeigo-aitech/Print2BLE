//
//  MyBLE.h
//  Print2BLE
//
//  Created by Larry Bank
//  Copyright (c) 2021 BitBank Software Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CoreBluetooth/CoreBluetooth.h"
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MyBLE : NSObject <CBCentralManagerDelegate>

@property (nonatomic, strong) CBCentralManager *centralManager;

- (instancetype)init;
- (void)startScan;
- (void)reportCurrentStateIfNotReady;
- (uint8_t)findPrinter: (const char *) name;
- (void)writeData: (uint8_t *)pData withLength:(int)len withResponse:(bool)response;
- (void)preGraphics: (int)height;
- (void)postGraphics;
- (void)feedPaper;
- (int)getWidth;
- (NSString *)getName;
- (bool)isConnected;
- (void)scanLine: (uint8_t *)pData withLength:(int)len;
- (uint8_t)CheckSum:(uint8_t *)pData withLength: (int) iLen;
// Manual device selection (in addition to the auto-connect-on-known-name
// behavior in didDiscoverPeripheral:), and a clean disconnect so the user
// can retry without restarting the app.
- (void)connectToDiscoveredPeripheralAtIndex:(NSInteger)index;
- (void)disconnectPrinter;

@property (retain) NSMutableArray *discoveredPeripherals;
@property (retain) NSMutableArray<CBPeripheral *> *foundPeripherals; // every named device seen this scan, for manual selection
@property (strong, nonatomic) CBCentralManager * manager;
@property (atomic) int count;
@property (nonatomic) dispatch_queue_t bleQueue;
@property (nonatomic) CBPeripheral *myPeripheral;
@property (nonatomic) CBCharacteristic *myChar;
@property (nonatomic) bool bConnected;
@property (nonatomic) uint8_t ucPrinterType;
@property (copy) NSString *manufacturer;
@property (nonatomic) bool scanRequested; // startScan was called before Bluetooth finished powering on

enum {
  PRINTER_MTP2=0,
  PRINTER_MTP3,
  PRINTER_CAT,
  PRINTER_PERIPAGEPLUS,
  PRINTER_PERIPAGE,
  PRINTER_PANDA,
  PRINTER_COUNT
};

@end

NS_ASSUME_NONNULL_END
