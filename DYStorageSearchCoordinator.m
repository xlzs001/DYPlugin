#import "DYStorageSearchCoordinator.h"

#import <UIKit/UIKit.h>
#import <math.h>

static UITableView *DYStorageSearchFindTableView(UIView *view, NSInteger depth) {
    if (!view || depth < 0) return nil;
    if ([view isKindOfClass:[UITableView class]]) return (UITableView *)view;
    for (UIView *subview in view.subviews) {
        UITableView *tableView = DYStorageSearchFindTableView(subview, depth - 1);
        if (tableView) return tableView;
    }
    return nil;
}

static BOOL DYStorageSearchSetValue(id object, id value, NSString *key) {
    if (!object || key.length == 0) return NO;
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

@interface DYStorageSearchCoordinator () <UITextFieldDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) id viewModel;
@property (nonatomic, weak) UITableView *tableView;
@property (nonatomic, copy) DYStorageSearchSectionsProvider sectionsProvider;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic) UIEdgeInsets originalContentInset;
@property (nonatomic) UIEdgeInsets originalIndicatorInset;
@property (nonatomic) BOOL installedInsets;
@property (nonatomic) NSUInteger pendingSearchGeneration;
@property (nonatomic, copy) dispatch_block_t pendingSearchBlock;
@property (nonatomic, copy) NSString *lastAppliedQuery;
@property (nonatomic, weak) UINavigationController *navigationController;
@property (nonatomic, strong) UIPanGestureRecognizer *searchBackGestureRecognizer;
@property (nonatomic) BOOL previousInteractivePopGestureEnabled;
@property (nonatomic) BOOL hasStoredInteractivePopGestureEnabled;
@property (nonatomic) BOOL handlingSearchBackGesture;
@property (nonatomic) BOOL pageVisible;
@property (nonatomic, copy) NSArray<UIGestureRecognizer *> *suppressedNavigationGestures;
@property (nonatomic, copy) NSArray<NSNumber *> *suppressedNavigationGestureStates;
- (BOOL)installSearchHeader;
- (NSString *)trimmedQuery;
- (BOOL)isSearchInteractionActive;
- (BOOL)isTopController;
- (void)updateSupplementaryViewsForQuery:(NSString *)query;
- (void)installNavigationInterceptors;
- (void)updateNavigationGestureState;
- (void)restoreNavigationGestureState;
- (BOOL)handleBackNavigationRequest;
- (void)handleSearchBackGesture:(UIPanGestureRecognizer *)gestureRecognizer;
- (void)searchTextDidChange:(UITextField *)textField;
- (void)cancelPendingSearchRefresh;
@end

@implementation DYStorageSearchCoordinator

+ (instancetype)installOnController:(UIViewController *)controller
                            viewModel:(id)viewModel
                     sectionsProvider:(DYStorageSearchSectionsProvider)sectionsProvider {
    if (!controller || !viewModel || !sectionsProvider) return nil;
    DYStorageSearchCoordinator *coordinator = [[self alloc] init];
    coordinator.controller = controller;
    coordinator.viewModel = viewModel;
    coordinator.sectionsProvider = sectionsProvider;
    if (![coordinator installSearchHeader]) return nil;
    return coordinator;
}

- (BOOL)installSearchHeader {
    [self.controller view];
    UITableView *tableView = DYStorageSearchFindTableView(self.controller.view, 8);
    if (!tableView) return NO;
    self.tableView = tableView;

    CGFloat width = MAX(CGRectGetWidth(tableView.bounds), CGRectGetWidth(self.controller.view.bounds));
    self.headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(width, 0), 52)];
    self.headerView.backgroundColor = UIColor.clearColor;
    self.headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    self.containerView = [[UIView alloc] initWithFrame:CGRectMake(16, 4, MAX(width - 32, 0), 44)];
    self.containerView.layer.cornerRadius = 12;
    self.containerView.layer.masksToBounds = NO;
    self.containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [self.headerView addSubview:self.containerView];

    self.searchTextField = [[UITextField alloc] initWithFrame:self.containerView.bounds];
    self.searchTextField.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.searchTextField.backgroundColor = UIColor.clearColor;
    UIFont *baseFont = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.searchTextField.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:baseFont];
    self.searchTextField.adjustsFontForContentSizeCategory = YES;
    self.searchTextField.clearButtonMode = UITextFieldViewModeWhileEditing;
    self.searchTextField.returnKeyType = UIReturnKeySearch;
    self.searchTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.searchTextField.spellCheckingType = UITextSpellCheckingTypeNo;
    self.searchTextField.delegate = self;
    self.searchTextField.accessibilityLabel = @"DYStorage聚合搜索";
    self.searchTextField.placeholder = @"搜索设置项";

    UIView *leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 38, 30)];
    UIImageView *leftIcon = [[UIImageView alloc] initWithFrame:CGRectMake(14, 6, 18, 18)];
    leftIcon.image = [UIImage systemImageNamed:@"magnifyingglass"];
    leftIcon.contentMode = UIViewContentModeScaleAspectFit;
    leftIcon.tintColor = UIColor.secondaryLabelColor;
    [leftView addSubview:leftIcon];
    self.searchTextField.leftView = leftView;
    // Keep a stable text origin while editing. Switching the left icon on
    // after the first character moved both the insertion caret and text.
    self.searchTextField.leftViewMode = UITextFieldViewModeAlways;
    [self.searchTextField addTarget:self action:@selector(searchTextDidChange:) forControlEvents:UIControlEventEditingChanged];
    [self.containerView addSubview:self.searchTextField];

    self.containerView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.containerView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.containerView.layer.shadowOpacity = 0.08;
    self.containerView.layer.shadowOffset = CGSizeMake(0, 3);
    self.containerView.layer.shadowRadius = 3.5;
    self.searchTextField.textColor = UIColor.labelColor;
    self.searchTextField.tintColor = UIColor.systemBlueColor;

    [self.controller.view addSubview:self.headerView];
    self.originalContentInset = tableView.contentInset;
    self.originalIndicatorInset = tableView.scrollIndicatorInsets;
    UIEdgeInsets contentInset = tableView.contentInset;
    contentInset.top += CGRectGetHeight(self.headerView.bounds);
    tableView.contentInset = contentInset;
    UIEdgeInsets indicatorInset = tableView.scrollIndicatorInsets;
    indicatorInset.top += CGRectGetHeight(self.headerView.bounds);
    tableView.scrollIndicatorInsets = indicatorInset;
    self.installedInsets = YES;
    [self installNavigationInterceptors];
    [self updateLayout];
    return YES;
}

- (NSString *)trimmedQuery {
    return [self.searchTextField.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (BOOL)isSearchInteractionActive {
    return self.searchTextField.isFirstResponder || [self trimmedQuery].length > 0;
}

- (BOOL)isTopController {
    UIViewController *controller = self.controller;
    if (!self.pageVisible || !controller.viewIfLoaded.window) return NO;
    UINavigationController *navigationController = controller.navigationController;
    if (!navigationController) return YES;
    UIViewController *visibleController = navigationController.visibleViewController ?:
                                          navigationController.topViewController;
    for (UIViewController *candidate = controller; candidate; candidate = candidate.parentViewController) {
        if (candidate == visibleController) return YES;
    }
    return NO;
}

- (void)installNavigationInterceptors {
    UIViewController *controller = self.controller;
    if (!controller) return;

    UINavigationController *navigationController = controller.navigationController;
    if (self.navigationController != navigationController) {
        [self restoreNavigationGestureState];
        [self.searchBackGestureRecognizer.view removeGestureRecognizer:self.searchBackGestureRecognizer];
        self.navigationController = navigationController;
    }

    if (!self.searchBackGestureRecognizer) {
        UIPanGestureRecognizer *gestureRecognizer =
            [[UIPanGestureRecognizer alloc] initWithTarget:self
                                                    action:@selector(handleSearchBackGesture:)];
        gestureRecognizer.maximumNumberOfTouches = 1;
        gestureRecognizer.cancelsTouchesInView = YES;
        gestureRecognizer.delegate = self;
        gestureRecognizer.enabled = NO;
        self.searchBackGestureRecognizer = gestureRecognizer;
    }
    UIView *gestureHost = navigationController.view ?: controller.view;
    if (gestureHost && self.searchBackGestureRecognizer.view != gestureHost) {
        [self.searchBackGestureRecognizer.view removeGestureRecognizer:self.searchBackGestureRecognizer];
        [gestureHost addGestureRecognizer:self.searchBackGestureRecognizer];
    }
    [self updateNavigationGestureState];
}

- (void)updateNavigationGestureState {
    UINavigationController *navigationController = self.controller.navigationController;
    UIGestureRecognizer *interactivePopGesture = navigationController.interactivePopGestureRecognizer;
    BOOL shouldIntercept = [self isTopController] &&
        (self.handlingSearchBackGesture || [self isSearchInteractionActive]);

    self.searchBackGestureRecognizer.enabled = shouldIntercept;
    if (shouldIntercept) {
        if (!self.hasStoredInteractivePopGestureEnabled && interactivePopGesture) {
            self.previousInteractivePopGestureEnabled = interactivePopGesture.enabled;
            self.hasStoredInteractivePopGestureEnabled = YES;
        }
        if (!self.suppressedNavigationGestures.count) {
            NSMutableArray<UIGestureRecognizer *> *gestures = [NSMutableArray array];
            NSMutableArray<NSNumber *> *states = [NSMutableArray array];
            for (UIGestureRecognizer *gesture in navigationController.view.gestureRecognizers) {
                if (gesture == self.searchBackGestureRecognizer ||
                    ![gesture isKindOfClass:[UIPanGestureRecognizer class]]) continue;
                [gestures addObject:gesture];
                [states addObject:@(gesture.enabled)];
                gesture.enabled = NO;
            }
            self.suppressedNavigationGestures = gestures;
            self.suppressedNavigationGestureStates = states;
        }
        interactivePopGesture.enabled = NO;
    } else {
        [self restoreNavigationGestureState];
    }
}

- (void)restoreNavigationGestureState {
    NSUInteger stateCount = self.suppressedNavigationGestureStates.count;
    [self.suppressedNavigationGestures enumerateObjectsUsingBlock:^(UIGestureRecognizer *gesture,
                                                                    NSUInteger index,
                                                                    __unused BOOL *stop) {
        if (index < stateCount) gesture.enabled = self.suppressedNavigationGestureStates[index].boolValue;
    }];
    self.suppressedNavigationGestures = nil;
    self.suppressedNavigationGestureStates = nil;
    if (self.hasStoredInteractivePopGestureEnabled) {
        self.navigationController.interactivePopGestureRecognizer.enabled =
            self.previousInteractivePopGestureEnabled;
        self.hasStoredInteractivePopGestureEnabled = NO;
    }
    self.searchBackGestureRecognizer.enabled = NO;
}

- (BOOL)handleBackNavigationRequest {
    if (![self isTopController] || ![self isSearchInteractionActive]) return NO;

    // The first horizontal back swipe exits search and restores the complete hub.
    // A following swipe is handled by UINavigationController and returns to
    // Douyin settings, matching the two visible page levels.
    [self cancelPendingSearchRefresh];
    self.searchTextField.text = @"";
    [self.searchTextField resignFirstResponder];
    [self refreshWithCurrentQuery];
    [self updateNavigationGestureState];
    return YES;
}

- (void)handleSearchBackGesture:(UIPanGestureRecognizer *)gestureRecognizer {
    switch (gestureRecognizer.state) {
        case UIGestureRecognizerStateBegan:
            // Keep the system pop gesture disabled until this complete touch
            // sequence ends. Re-enabling it while the finger was still moving
            // allowed the same swipe to clear search and pop the hub at once.
            self.handlingSearchBackGesture = YES;
            if (![self handleBackNavigationRequest]) {
                self.handlingSearchBackGesture = NO;
                [self updateNavigationGestureState];
            }
            break;
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            self.handlingSearchBackGesture = NO;
            __weak DYStorageSearchCoordinator *weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf updateNavigationGestureState];
            });
            break;
        }
        default:
            break;
    }
}

- (void)updateSupplementaryViewsForQuery:(NSString *)query {
    BOOL searching = query.length > 0;
    for (UIView *subview in self.controller.view.subviews) {
        if ([subview.accessibilityIdentifier isEqualToString:@"DYStorageAboutFooter"]) {
            subview.hidden = searching;
        }
    }
}

- (void)refreshWithCurrentQuery {
    if (!self.sectionsProvider || !self.viewModel) return;
    NSString *query = [self trimmedQuery];
    BOOL queryChanged = ![query isEqualToString:self.lastAppliedQuery ?: @""];
    [self updateSupplementaryViewsForQuery:query];
    NSArray *sections = self.sectionsProvider(query) ?: @[];
    if (!DYStorageSearchSetValue(self.viewModel, sections, @"sectionDataArray")) return;
    UITableView *tableView = self.tableView;
    [tableView reloadData];
    if (queryChanged && tableView) {
        // Search is a high-frequency action. Reset immediately instead of
        // animating the list on every character typed.
        CGPoint topOffset = CGPointMake(tableView.contentOffset.x, -tableView.adjustedContentInset.top);
        [tableView setContentOffset:topOffset animated:NO];
    }
    self.lastAppliedQuery = query;
}

- (void)searchTextDidChange:(__unused UITextField *)textField {
    [self updateSupplementaryViewsForQuery:[self trimmedQuery]];
    [self updateNavigationGestureState];
    // Building native private-setting models for hundreds of catalog entries
    // is deliberately kept off the per-keystroke hot path. Coalesce rapid
    // edits so only the final query refreshes the table.
    [self cancelPendingSearchRefresh];
    NSUInteger generation = self.pendingSearchGeneration;
    __weak DYStorageSearchCoordinator *weakSelf = self;
    dispatch_block_t searchBlock = dispatch_block_create(0, ^{
        DYStorageSearchCoordinator *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.pendingSearchGeneration) return;
        if (![strongSelf isTopController]) return;
        strongSelf.pendingSearchBlock = nil;
        [strongSelf refreshWithCurrentQuery];
    });
    self.pendingSearchBlock = searchBlock;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), searchBlock);
}

- (void)cancelPendingSearchRefresh {
    if (self.pendingSearchBlock) dispatch_block_cancel(self.pendingSearchBlock);
    self.pendingSearchBlock = nil;
    ++self.pendingSearchGeneration;
}

- (void)updateLayout {
    UITableView *tableView = self.tableView;
    if (!tableView || !self.headerView) return;
    UIView *superview = tableView.superview;
    if (!superview) return;
    CGRect tableFrame = [superview convertRect:tableView.frame toView:self.controller.view];
    CGFloat automaticTopInset = MAX(0, tableView.adjustedContentInset.top - tableView.contentInset.top);
    CGFloat width = CGRectGetWidth(tableView.bounds);
    CGRect headerFrame = CGRectMake(CGRectGetMinX(tableFrame),
                                    CGRectGetMinY(tableFrame) + automaticTopInset,
                                    width,
                                    52);
    CGRect containerFrame = CGRectMake(16, 4, MAX(width - 32, 0), 44);
    BOOL headerChanged = !CGRectEqualToRect(self.headerView.frame, headerFrame);
    BOOL containerChanged = !CGRectEqualToRect(self.containerView.frame, containerFrame) ||
                            self.containerView.layer.shadowPath == NULL;

    if (headerChanged) self.headerView.frame = headerFrame;
    if (containerChanged) {
        self.containerView.frame = containerFrame;
        self.containerView.layer.shadowPath =
            [UIBezierPath bezierPathWithRoundedRect:self.containerView.bounds cornerRadius:12].CGPath;
        self.searchTextField.frame = self.containerView.bounds;
    }

    // Do not force the search field to the front on every layout pass. Plug-in
    // sheets and floating panels added later must remain above DYStorage, and
    // repeated z-order mutations can trigger more layout work.
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidBeginEditing:(__unused UITextField *)textField {
    [self updateNavigationGestureState];
}

- (void)textFieldDidEndEditing:(__unused UITextField *)textField {
    [self updateNavigationGestureState];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.searchBackGestureRecognizer) {
        if (![self isTopController] || ![self isSearchInteractionActive]) return NO;
        CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:gestureRecognizer.view];
        return velocity.x > fabs(velocity.y) * 1.15;
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer
       shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer != self.searchBackGestureRecognizer) return YES;
    UIView *touchView = touch.view;
    if (!touchView) return NO;
    BOOL inSearchHeader = self.headerView &&
        (touchView == self.headerView || [touchView isDescendantOfView:self.headerView]);
    BOOL inSourceTable = self.tableView &&
        (touchView == self.tableView || [touchView isDescendantOfView:self.tableView]);
    // Floating plug-ins may draw directly above the DYStorage controller without
    // presenting another UIViewController. Ignore touches from those overlays
    // so the organizer's full-width back gesture cannot swallow their controls.
    return inSearchHeader || inSourceTable;
}

- (void)pageDidAppear {
    self.pageVisible = YES;
    [self installNavigationInterceptors];
    [self updateNavigationGestureState];
}

- (void)pageDidDisappear {
    [self cancelPendingSearchRefresh];
    self.pageVisible = NO;
    self.handlingSearchBackGesture = NO;
    [self restoreNavigationGestureState];
}

- (void)dealloc {
    [self cancelPendingSearchRefresh];
    [self restoreNavigationGestureState];
    [_searchBackGestureRecognizer.view removeGestureRecognizer:_searchBackGestureRecognizer];
    [_searchTextField removeTarget:self action:@selector(searchTextDidChange:) forControlEvents:UIControlEventEditingChanged];
    UITableView *tableView = self.tableView;
    if (tableView && self.installedInsets) {
        tableView.contentInset = self.originalContentInset;
        tableView.scrollIndicatorInsets = self.originalIndicatorInset;
    }
}

@end
