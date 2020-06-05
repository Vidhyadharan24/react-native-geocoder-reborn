#import <React/RCTBridgeModule.h>
#import <React/RCTConvert.h>

#import <CoreLocation/CoreLocation.h>
@import GoogleMaps;

@interface RCTConvert (CoreLocation)
+ (CLLocation *)CLLocation:(id)json;
@end

@interface RNGeocoder : NSObject<RCTBridgeModule>
@property (nonatomic, strong) CLGeocoder *geocoder;
@end
