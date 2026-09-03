#import <Foundation/Foundation.h>

@class UIViewController;

/// Developer-only recorder used to produce the static aggregate-search catalog.
/// It records setting metadata only while explicitly enabled by the developer.
@interface DYStorageDeveloperScanner : NSObject

+ (instancetype)sharedScanner;

@property (nonatomic, readonly, getter=isScanning) BOOL scanning;
@property (nonatomic, readonly) NSUInteger recordCount;

- (void)startNewScan;
- (void)stopScanning;
- (void)selectPluginWithTitle:(NSString *)pluginTitle;
- (void)captureSettingsController:(UIViewController *)controller viewModel:(id)viewModel;
- (BOOL)exportReportFromController:(UIViewController *)controller error:(NSError **)error;

@end
