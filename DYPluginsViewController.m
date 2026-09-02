#import "DYPluginsViewController.h"
#import "DYPluginsMgr.h"

@implementation DYPluginsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"插件管理中枢";
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.dataSource = [DYPluginsMgr sharedInstance].plugins;
    
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DYPluginModel *model = self.dataSource[indexPath.row];
    
    if (model.isController) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DYNavCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"DYNavCell"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cell.textLabel.text = model.title;
        cell.detailTextLabel.text = model.version ?: @"";
        return cell;
    } else {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DYSwitchCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"DYSwitchCell"];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            UISwitch *sw = [[UISwitch alloc] init];
            [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = sw;
        }
        cell.textLabel.text = model.title;
        UISwitch *sw = (UISwitch *)cell.accessoryView;
        sw.tag = indexPath.row;
        sw.on = [[NSUserDefaults standardUserDefaults] boolForKey:model.key];
        return cell;
    }
}

- (void)switchChanged:(UISwitch *)sender {
    DYPluginModel *model = self.dataSource[sender.tag];
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:model.key];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    DYPluginModel *model = self.dataSource[indexPath.row];
    
    if (model.isController && model.controllerName.length > 0) {
        Class targetClass = NSClassFromString(model.controllerName);
        if (targetClass) {
            UIViewController *targetVC = [[targetClass alloc] init];
            targetVC.title = model.title;
            [self.navigationController pushViewController:targetVC animated:YES];
        }
    }
}
@end
