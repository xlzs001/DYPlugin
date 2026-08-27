#import <Foundation/Foundation.h>

@interface DYPluginModel : NSObject
@property (nonatomic, assign) BOOL isController;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *controllerName;
@property (nonatomic, copy) NSString *key;
@end

