#import "RNGeocoder.h"

#import <CoreLocation/CoreLocation.h>

#import <React/RCTConvert.h>

@implementation RCTConvert (CoreLocation)

+ (CLLocation *)CLLocation:(id)json
{
    json = [self NSDictionary:json];

    double lat = [RCTConvert double:json[@"lat"]];
    double lng = [RCTConvert double:json[@"lng"]];
    return [[CLLocation alloc] initWithLatitude:lat longitude:lng];
}

@end

@implementation RNGeocoder

RCT_EXPORT_MODULE();

RCT_EXPORT_METHOD(geocodePosition:(CLLocation *)location
                  gmsKey:(NSString *)gmsKey
                  locale:(NSLocale *)locale
                  maxResult:(int)maxResult
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self.geocoder && !gmsKey) {
        self.geocoder = [[CLGeocoder alloc] init];
    } else {
        @try {
            dispatch_sync(dispatch_get_main_queue(), ^{
                [GMSServices sharedServices];
            });
        }
        @catch (NSException *exception) {
            if (!gmsKey) {
                [GMSServices provideAPIKey: gmsKey];
            } else {
                NSMutableDictionary * info = [NSMutableDictionary dictionary];
                [info setValue:exception.name forKey:@"ExceptionName"];
                [info setValue:exception.reason forKey:@"ExceptionReason"];
                [info setValue:exception.callStackReturnAddresses forKey:@"ExceptionCallStackReturnAddresses"];
                [info setValue:exception.callStackSymbols forKey:@"ExceptionCallStackSymbols"];
                [info setValue:exception.userInfo forKey:@"ExceptionUserInfo"];

                NSError *error = [[NSError alloc] initWithDomain:@"Google maps" code:0 userInfo:info];
                return reject(@"GOOGLEMAPS_ERROR", @"Google maps service has not been initialized, pass the key in options", error);
            }
        }
    }

    if (self.geocoder && self.geocoder.geocoding) {
        [self.geocoder cancelGeocode];
    }
    
    if (self.geocoder) {
        CLGeocodeCompletionHandler handler = ^void(NSArray< CLPlacemark *> *placemarks, NSError *error) {
            if (error) {
                if (placemarks.count == 0) {
                    return reject(@"EMPTY_RESULT", @"Geocoder returned an empty list.", error);
                }

                return reject(@"NATIVE_ERROR", @"reverseGeocodeLocation failed.", error);
            }
            resolve([self placemarksToDictionary:placemarks maxResult:maxResult]);
        };

        if (@available(iOS 11.0, *)) {
            [self.geocoder reverseGeocodeLocation:location
                                  preferredLocale:locale
                                completionHandler:handler];
        } else {
            [self.geocoder reverseGeocodeLocation:location completionHandler:handler];
        }
    } else {
        GMSReverseGeocodeCallback handler = ^(GMSReverseGeocodeResponse * response, NSError * error) {
            if (error) {
                if (response.results.count == 0) {
                    return reject(@"EMPTY_RESULT", @"Geocoder returned an empty list.", error);
                }

                return reject(@"NATIVE_ERROR", @"reverseGeocodeLocation failed.", error);
            }
            resolve([self gmsResultsToDictionary:response.results maxResult:maxResult]);
        };
        dispatch_async(dispatch_get_main_queue(), ^{
            [[GMSGeocoder geocoder] reverseGeocodeCoordinate: location.coordinate completionHandler: handler];
        });
    }
}

RCT_EXPORT_METHOD(geocodeAddress:(NSString *)address
                  locale:(NSLocale *)locale
                  maxResult:(int)maxResult
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self.geocoder) {
        self.geocoder = [[CLGeocoder alloc] init];
    }

    if (self.geocoder.geocoding) {
      [self.geocoder cancelGeocode];
    }

    CLGeocodeCompletionHandler handler = ^void(NSArray< CLPlacemark *> *placemarks, NSError *error) {
        if (error) {
            if (placemarks.count == 0) {
              return reject(@"NOT_FOUND", @"Geocoder returned an empty list.", error);
            }
            return reject(@"NATIVE_ERROR", @"geocodeAddressString failed.", error);
        }
        resolve([self placemarksToDictionary:placemarks maxResult:maxResult]);
    };

    if (@available(iOS 11.0, *)) {
        [self.geocoder geocodeAddressString:address inRegion:nil preferredLocale:locale completionHandler:handler];
    } else {
        [self.geocoder geocodeAddressString:address completionHandler:handler];
    }
}

RCT_EXPORT_METHOD(geocodeAddressInRegion:(NSString *)address
                  lat:(double)lat
                  lng:(double)lng
                  radius:(double)radius
                  locale:(NSLocale *)locale
                  maxResult:(int)maxResult
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self.geocoder) {
        self.geocoder = [[CLGeocoder alloc] init];
    }

    if (self.geocoder.geocoding) {
      [self.geocoder cancelGeocode];
    }

    CLLocationCoordinate2D center = CLLocationCoordinate2DMake(lat, lng);
    CLRegion* region = [[CLCircularRegion alloc] initWithCenter:center radius:radius identifier:@"Search Radius"];

    CLGeocodeCompletionHandler handler = ^void(NSArray< CLPlacemark *> *placemarks, NSError *error) {
        if (error) {
            if (placemarks.count == 0) {
              return reject(@"NOT_FOUND", @"Geocoder returned an empty list.", error);
            }
            return reject(@"NATIVE_ERROR", @"geocodeAddressString failed.", error);
        }
        resolve([self placemarksToDictionary:placemarks maxResult:maxResult]);
    };

    if (@available(iOS 11.0, *)) {
        [self.geocoder geocodeAddressString:address inRegion:region preferredLocale:locale completionHandler:handler];
    } else {
        [self.geocoder geocodeAddressString:address completionHandler:handler];
    }
}

- (NSArray *)placemarksToDictionary:(NSArray *)placemarks
                          maxResult:(int)maxResult{

    NSMutableArray *results = [[NSMutableArray alloc] init];

    for (int i = 0; i < placemarks.count; i++) {
        if (i == maxResult) {
            break;
        }
        CLPlacemark* placemark = [placemarks objectAtIndex:i];

        NSString *name = nil;

        if (![placemark.name isEqualToString:placemark.locality] &&
            ![placemark.name isEqualToString:placemark.thoroughfare] &&
            ![placemark.name isEqualToString:placemark.subThoroughfare])
        {
            name = placemark.name;
        }

        NSArray *lines = placemark.addressDictionary[@"FormattedAddressLines"];

        NSDictionary *result = @{
            @"feature": name ?: [NSNull null],
            @"position": @{
                 @"lat": [NSNumber numberWithDouble:placemark.location.coordinate.latitude],
                 @"lng": [NSNumber numberWithDouble:placemark.location.coordinate.longitude],
                 },
            @"country": placemark.country ?: [NSNull null],
            @"countryCode": placemark.ISOcountryCode ?: [NSNull null],
            @"locality": placemark.locality ?: [NSNull null],
            @"subLocality": placemark.subLocality ?: [NSNull null],
            @"streetName": placemark.thoroughfare ?: [NSNull null],
            @"streetNumber": placemark.subThoroughfare ?: [NSNull null],
            @"postalCode": placemark.postalCode ?: [NSNull null],
            @"adminArea": placemark.administrativeArea ?: [NSNull null],
            @"subAdminArea": placemark.subAdministrativeArea ?: [NSNull null],
            @"formattedAddress": [lines componentsJoinedByString:@", "] ?: [NSNull null]
        };

        [results addObject:result];
    }

    return results;

}

- (NSArray *)gmsResultsToDictionary:(NSArray<GMSAddress *> *)addresses
                          maxResult:(int)maxResult{

    NSMutableArray<NSDictionary *> *results = [[NSMutableArray alloc] init];

    for (int i = 0; i < addresses.count; i++) {
        if (i == maxResult) {
            break;
        }
        GMSAddress *address = [addresses objectAtIndex:i];
        
//        NSString *name = nil;
//
//        if (![address.name isEqualToString:address.locality] &&
//            ![address.name isEqualToString:address.thoroughfare] &&
//            ![address.name isEqualToString:address.subThoroughfare])
//        {
//            name = address.name;
//        }
                
        NSDictionary *result = @{
//            @"feature": name ?: [NSNull null],
            @"position": @{
                 @"lat": [NSNumber numberWithDouble:address.coordinate.latitude],
                 @"lng": [NSNumber numberWithDouble:address.coordinate.longitude],
                 },
            @"country": address.country ?: [NSNull null],
//            @"countryCode": placemark.ISOcountryCode ?: [NSNull null],
            @"locality": address.locality ?: [NSNull null],
            @"subLocality": address.subLocality ?: [NSNull null],
            @"streetName": address.thoroughfare ?: [NSNull null],
//            @"streetNumber": placemark.subThoroughfare ?: [NSNull null],
            @"postalCode": address.postalCode ?: [NSNull null],
            @"adminArea": address.administrativeArea ?: [NSNull null],
//            @"subAdminArea": placemark.subAdministrativeArea ?: [NSNull null],
            @"formattedAddress": [address.lines componentsJoinedByString:@", "] ?: [NSNull null]
        };

        [results addObject:result];
    }

    return results;
}

@end
