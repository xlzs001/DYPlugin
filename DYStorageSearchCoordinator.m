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

@interface DYStorageSearchCoordinator () <UITextFieldDelegate>
@property (nonatomic, weak) UIViewController *controller;
@property (nonatomic, weak) id viewModel;
@property (nonatomic, copy) DYStorageSearchSectionsProvider sectionsProvider;
@property (nonatomic, strong) UIView *headerView;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) UITextField *searchTextField;
@property (nonatomic, strong) UIView *placeholderView;
@property (nonatomic, strong) UIImageView *placeholderIconView;
@property (nonatomic, strong) UILabel *placeholderLabel;
@property (nonatomic) UIEdgeInsets originalContentInset;
@property (nonatomic) UIEdgeInsets originalIndicatorInset;
@property (nonatomic) BOOL installedInsets;
- (BOOL)installSearchHeader;
- (NSString *)trimmedQuery;
- (void)updatePlaceholderAnimated:(BOOL)animated;
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

    UIView *leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 38, 30)];
    UIImageView *leftIcon = [[UIImageView alloc] initWithFrame:CGRectMake(14, 6, 18, 18)];
    leftIcon.image = [UIImage systemImageNamed:@"magnifyingglass"];
    leftIcon.contentMode = UIViewContentModeScaleAspectFit;
    leftIcon.tintColor = UIColor.secondaryLabelColor;
    [leftView addSubview:leftIcon];
    self.searchTextField.leftView = leftView;
    self.searchTextField.leftViewMode = UITextFieldViewModeNever;
    [self.searchTextField addTarget:self action:@selector(searchTextDidChange:) forControlEvents:UIControlEventEditingChanged];
    [self.containerView addSubview:self.searchTextField];

    self.placeholderView = [[UIView alloc] initWithFrame:CGRectZero];
    self.placeholderView.userInteractionEnabled = NO;
    [self.containerView addSubview:self.placeholderView];

    self.placeholderIconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]];
    self.placeholderIconView.contentMode = UIViewContentModeScaleAspectFit;
    self.placeholderIconView.tintColor = UIColor.secondaryLabelColor;
    [self.placeholderView addSubview:self.placeholderIconView];

    self.placeholderLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.placeholderLabel.text = @"搜索设置项";
    self.placeholderLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.placeholderLabel.textColor = UIColor.secondaryLabelColor;
    [self.placeholderView addSubview:self.placeholderLabel];

    self.containerView.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    self.containerView.layer.shadowColor = UIColor.blackColor.CGColor;
    self.containerView.layer.shadowOpacity = 0.08;
    self.containerView.layer.shadowOffset = CGSizeMake(0, 3);
    self.containerView.layer.shadowRadius = 3.5;
    self.searchTextField.textColor = UIColor.labelColor;
    self.searchTextField.tintColor = UIColor.labelColor;

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

- (void)updatePlaceholderAnimated:(BOOL)animated {
    if (!self.placeholderView) return;
    BOOL hasText = self.searchTextField.text.length > 0;
    BOOL leftAligned = self.searchTextField.isEditing;
    CGFloat iconSize = 18;
    CGFloat spacing = 8;
    CGSize labelSize = [self.placeholderLabel.text sizeWithAttributes:@{NSFontAttributeName: self.placeholderLabel.font}];
    CGFloat placeholderWidth = iconSize + spacing + ceil(labelSize.width);
    CGFloat placeholderHeight = MAX(iconSize, ceil(labelSize.height));
    self.placeholderIconView.frame = CGRectMake(0, (placeholderHeight - iconSize) / 2, iconSize, iconSize);
    self.placeholderLabel.frame = CGRectMake(iconSize + spacing, 0, ceil(labelSize.width), placeholderHeight);
    CGFloat x = leftAligned ? 14 : (CGRectGetWidth(self.containerView.bounds) - placeholderWidth) / 2;
    CGRect targetFrame = CGRectMake(MAX(x, 0), (CGRectGetHeight(self.containerView.bounds) - placeholderHeight) / 2,
                                    placeholderWidth, placeholderHeight);
    void (^changes)(void) = ^{
        self.placeholderView.frame = targetFrame;
        self.placeholderView.alpha = hasText ? 0 : 1;
    };
    if (animated) {
        [UIView animateWithDuration:0.2 animations:changes];
    } else {
        changes();
    }
    self.searchTextField.leftViewMode = hasText ? UITextFieldViewModeAlways : UITextFieldViewModeNever;
}

- (void)refreshWithCurrentQuery {
    if (!self.sectionsProvider || !self.viewModel) return;
    NSArray *sections = self.sectionsProvider([self trimmedQuery]) ?: @[];
    if (!DYStorageSearchSetValue(self.viewModel, sections, @"sectionDataArray")) return;
    UITableView *tableView = DYStorageSearchFindTableView(self.controller.view, 8);
    [tableView reloadData];
}

- (void)searchTextDidChange:(__unused UITextField *)textField {
    [self updatePlaceholderAnimated:NO];
    [self refreshWithCurrentQuery];
}

- (void)updateLayout {
    UITableView *tableView = DYStorageSearchFindTableView(self.controller.view, 8);
    if (!tableView || !self.headerView) return;
    UIView *superview = tableView.superview;
    if (!superview) return;
    CGRect tableFrame = [superview convertRect:tableView.frame toView:self.controller.view];
    CGFloat automaticTopInset = MAX(0, tableView.adjustedContentInset.top - tableView.contentInset.top);
    CGFloat width = CGRectGetWidth(tableView.bounds);
    self.headerView.frame = CGRectMake(CGRectGetMinX(tableFrame), CGRectGetMinY(tableFrame) + automaticTopInset, width, 52);
    self.containerView.frame = CGRectMake(16, 4, MAX(width - 32, 0), 44);
    self.containerView.bounds = CGRectMake(0, 0, MAX(width - 32, 0), 44);
    self.containerView.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:self.containerView.bounds cornerRadius:12].CGPath;
    self.searchTextField.frame = self.containerView.bounds;
    [self updatePlaceholderAnimated:NO];
    [self.controller.view bringSubviewToFront:self.headerView];
}

- (void)textFieldDidBeginEditing:(__unused UITextField *)textField {
    [self updatePlaceholderAnimated:YES];
}

- (void)textFieldDidEndEditing:(__unused UITextField *)textField {
    [self updatePlaceholderAnimated:YES];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)dealloc {
    UITableView *tableView = self.controller.isViewLoaded ? DYStorageSearchFindTableView(self.controller.view, 8) : nil;
    if (tableView && self.installedInsets) {
        tableView.contentInset = self.originalContentInset;
        tableView.scrollIndicatorInsets = self.originalIndicatorInset;
    }
}

@end
