//
//  DTBTLEService.m
//  Deanna
//
//  Created by Charles Choi on 12/18/12.
//  Copyright (c) 2012 Yummy Melon Software. All rights reserved.
//
#include "TISensorTag.h"
#import "DTBTLEService.h"
#import "DTSensorTag.h"

static DTBTLEService *sharedBTLEService;

NSString * const DTBTLEServicePowerOffNotification = @"com.yummymelon.btleservice.power.off";

@implementation DTBTLEService

+ (DTBTLEService *)sharedService {
    if (sharedBTLEService == nil) {
        sharedBTLEService = [[super allocWithZone:NULL] init];
    }
    return sharedBTLEService;
}


- (id)init {
    self = [super init];
    
    if (self) {
        _peripherals = [[NSMutableArray alloc] init];
        _manager = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
    }
    
    return self;
}


- (BOOL)isSensorTagPeripheral:(CBPeripheral *)peripheral {
    BOOL result = NO;
    
    CBUUID *test = [CBUUID UUIDWithString:@"" kSensorTag_IDENTIFIER];
    CBUUID *control = [CBUUID UUIDWithCFUUID:peripheral.UUID];
    
    result = [test isEqual:control];
    return result;
}


- (void)persistPeripherals {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *devices = [[NSMutableArray alloc] init];
    
    for (CBPeripheral *p in self.peripherals) {
        CFStringRef uuidString = NULL;
        
        uuidString = CFUUIDCreateString(NULL, p.UUID);
        if (uuidString) {
            [devices addObject:(NSString *)CFBridgingRelease(uuidString)];
        }
    }

    [userDefaults setObject:devices forKey:@"storedPeripherals"];
    [userDefaults synchronize];
}


- (void)loadPeripherals {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    NSArray *devices = [userDefaults arrayForKey:@"storedPeripherals"];
    NSMutableArray *peripheralUUIDList = [[NSMutableArray alloc] init];
    
    if (![devices isKindOfClass:[NSArray class]]) {
        // TODO - need right error handler
        NSLog(@"No stored array to load");
    }
    
    for (id uuidString in devices) {
        if (![uuidString isKindOfClass:[NSString class]]) {
            continue;
        }
        
        CFUUIDRef uuid = CFUUIDCreateFromString(NULL, (CFStringRef)uuidString);
        
        if (!uuid)
            continue;
        
        [peripheralUUIDList addObject:(id)CFBridgingRelease(uuid)];
    }
    
    if ([peripheralUUIDList count] > 0) {
        [self.manager retrievePeripherals:peripheralUUIDList];
    }
    else {
        [self.manager scanForPeripheralsWithServices:nil options:nil];
    }
}



#pragma mark CBCentralManagerDelegate Protocol Methods

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    static CBCentralManagerState oldManagerState = -1;
    
    
    switch (central.state) {
        case CBCentralManagerStatePoweredOn:
            NSLog(@"cbcm powered on");
            //[self.manager scanForPeripheralsWithServices:nil options:nil];
            [self loadPeripherals];
            
            break;
            
        case CBCentralManagerStateUnknown:
            NSLog(@"cbcm unknown");
            break;
            
        case CBCentralManagerStatePoweredOff:
            NSLog(@"cbcm powered off");

            if (oldManagerState != -1) {
                [[NSNotificationCenter defaultCenter] postNotificationName:DTBTLEServicePowerOffNotification
                                                                    object:self];
                
            }
            break;
            
        case CBCentralManagerStateResetting:
            NSLog(@"cbcm resetting");
            break;
            
        case CBCentralManagerStateUnauthorized:
            NSLog(@"cbcm unauthorized");
            break;
            
        case CBCentralManagerStateUnsupported: {
            NSLog(@"cbcm unauthorized");
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@""
                                                            message:@""
                                                           delegate:nil
                                                  cancelButtonTitle:@"Dismiss"
                                                  otherButtonTitles:nil];
            
            [alert show];
            break;
        }
    }
    
    oldManagerState = central.state;
}


- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData
                  RSSI:(NSNumber *)RSSI {
    if (![self.peripherals containsObject:peripheral]) {
        if ([self isSensorTagPeripheral:peripheral]) {
            if (!peripheral.isConnected) {
                if (self.sensorTag == nil)
                    self.sensorTag = [[DTSensorTag alloc] init];
                [self.peripherals addObject:peripheral];
                peripheral.delegate = self.sensorTag;
                [central connectPeripheral:peripheral options:nil];
                
                [self.manager stopScan];
                self.sensorTagEnabled = YES;
            }
        }
    }
    
//    if (![self.peripherals containsObject:peripheral]) {
//        if ([self isSensorTagPeripheral:peripheral]) {
//            [self.peripherals addObject:peripheral];
//            self.sensorTag = [[DTSensorTag alloc] init];
//            peripheral.delegate = self.sensorTag;
//            
//            [central connectPeripheral:peripheral options:nil];
//
//            [self.manager stopScan];
//            self.sensorTagEnabled = YES;
//        }
//    }
    
}


- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral {
    // 6
    
    if ([self isSensorTagPeripheral:peripheral]) {
        
        [peripheral discoverServices:[self.sensorTag services]];

    }
    

}



- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"centralManager didDisconnectePeripheral");
    
    // TODO: need to figure out mechanism to to remove the UI bindings from this object.
    
    self.sensorTag = nil;
    [self.peripherals removeObject:peripheral];
    [self loadPeripherals];
    
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error {
    NSLog(@"centralManager didFailToConnectPeripheral");
}

- (void)centralManager:(CBCentralManager *)central didRetrieveConnectedPeripherals:(NSArray *)peripherals {
    NSLog(@"centralManager didRetrieveConnectedPeripheral");
    
}

- (void)centralManager:(CBCentralManager *)central didRetrievePeripherals:(NSArray *)peripherals {
    NSLog(@"centralManager didRetrievePeripherals");
    
    
    
    for (CBPeripheral *peripheral in peripherals) {
        if (![self.peripherals containsObject:peripheral]) {
            if ([self isSensorTagPeripheral:peripheral]) {
                if (!peripheral.isConnected) {
                    if (self.sensorTag == nil)
                        self.sensorTag = [[DTSensorTag alloc] init];
                    [self.peripherals addObject:peripheral];
                    peripheral.delegate = self.sensorTag;
                    [central connectPeripheral:peripheral options:nil];
                    
                    [self.manager stopScan];
                    self.sensorTagEnabled = YES;
                }
            }
        }
    }

//        if ([self isSensorTagPeripheral:peripheral]) {
//            [self.peripherals addObject:peripheral];
//            if (self.sensorTag == nil)
//                self.sensorTag = [[DTSensorTag alloc] init];
//
//            peripheral.delegate = self.sensorTag;
//            [central connectPeripheral:peripheral options:nil];
//            self.sensorTagEnabled = YES;
//        }
//    }
//    
}


@end
