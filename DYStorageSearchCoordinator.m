#import "DYStorageSearchCoordinator.h"

#import <UIKit/UIKit.h>

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

@interface DYStorageSearchCoordinator () <UITextFieldDelegate>
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
- (BOOL)installSearchHeader;
- (NSString *)trimmedQuery;
- (void)updateSupplementaryViewsForQuery:(NSString *)query;
- (void)searchTextDidChange:(UITextField *)textField;
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
    self.searchTextField.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
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
    [self updateLayout];
    return YES;
}

- (NSString *)trimmedQuery {
    return [self.searchTextField.text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
    [self updateSupplementaryViewsForQuery:query];
    NSArray *sections = self.sectionsProvider(query) ?: @[];
    if (!DYStorageSearchSetValue(self.viewModel, sections, @"sectionDataArray")) return;
    UITableView *tableView = self.tableView;
    [tableView reloadData];
}

- (void)searchTextDidChange:(__unused UITextField *)textField {
    [self updateSupplementaryViewsForQuery:[self trimmedQuery]];
    // Building native private-setting models for hundreds of catalog entries
    // is deliberately kept off the per-keystroke hot path. Coalesce rapid
    // edits so only the final query refreshes the table.
    NSUInteger generation = ++self.pendingSearchGeneration;
    __weak DYStorageSearchCoordinator *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        DYStorageSearchCoordinator *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.pendingSearchGeneration) return;
        if (!strongSelf.controller.viewIfLoaded.window) return;
        [strongSelf refreshWithCurrentQuery];
    });
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

    // Reordering a subview on every layout pass can itself schedule additional
    // layout work on some Douyin versions. Only reorder when another injected
    // view has actually covered the search header.
    if (self.headerView.superview == self.controller.view &&
        self.controller.view.subviews.lastObject != self.headerView) {
        [self.controller.view bringSubviewToFront:self.headerView];
    }
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)dealloc {
    ++_pendingSearchGeneration;
    [_searchTextField removeTarget:self action:@selector(searchTextDidChange:) forControlEvents:UIControlEventEditingChanged];
    UITableView *tableView = self.tableView;
    if (tableView && self.installedInsets) {
        tableView.contentInset = self.originalContentInset;
        tableView.scrollIndicatorInsets = self.originalIndicatorInset;
    }
}

@end
