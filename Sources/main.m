#import <Cocoa/Cocoa.h>

static NSArray<NSString *> *DefaultDomains(void) {
    return @[
        @"vk.com", @"www.vk.com", @"m.vk.com", @"api.vk.com", @"id.vk.com",
        @"userapi.com", @"vkuseraudio.net", @"vkuseraudio.com", @"vkuserlive.net", @"vk-cdn.net",
        @"wildberries.ru", @"www.wildberries.ru", @"global.wildberries.ru", @"wbbasket.ru",
        @"basket-01.wbbasket.ru", @"basket-02.wbbasket.ru", @"basket-03.wbbasket.ru",
        @"basket-04.wbbasket.ru", @"basket-05.wbbasket.ru", @"static-basket-01.wbbasket.ru",
        @"static-basket-02.wbbasket.ru", @"static-basket-03.wbbasket.ru",
        @"static-basket-04.wbbasket.ru", @"static-basket-05.wbbasket.ru",
        @"ozon.ru", @"www.ozon.ru", @"api.ozon.ru", @"seller.ozon.ru", @"ozone.ru",
        @"cdn1.ozone.ru", @"cdn2.ozone.ru", @"cdn3.ozone.ru", @"ir.ozone.ru",
        @"pinterest.com", @"www.pinterest.com", @"ru.pinterest.com", @"pin.it", @"pinimg.com",
        @"www.pinimg.com", @"i.pinimg.com", @"s.pinimg.com", @"assets.pinterest.com",
        @"yandex.ru", @"www.yandex.ru", @"ya.ru", @"yandex.com", @"yandex.net", @"yandex.kz",
        @"id.yandex.ru", @"passport.yandex.ru", @"mail.yandex.ru", @"disk.yandex.ru",
        @"maps.yandex.ru", @"music.yandex.ru", @"market.yandex.ru", @"translate.yandex.ru",
        @"metrika.yandex.ru", @"mc.yandex.ru", @"direct.yandex.ru", @"yandex.cloud",
        @"console.yandex.cloud", @"cloud.yandex.ru", @"yandexcloud.net", @"kinopoisk.ru",
        @"www.kinopoisk.ru", @"auto.ru", @"www.auto.ru", @"edadeal.ru", @"www.edadeal.ru",
        @"bookmate.ru", @"www.bookmate.ru"
    ];
}

static NSString *ShellQuote(NSString *value) {
    return [NSString stringWithFormat:@"'%@'", [value stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

static NSString *AppleScriptQuote(NSString *value) {
    NSString *escaped = [value stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    return [NSString stringWithFormat:@"\"%@\"", escaped];
}

static NSString *NormalizeDomain(NSString *value) {
    NSString *domain = [[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if ([domain containsString:@"://"]) {
        NSURLComponents *parts = [NSURLComponents componentsWithString:domain];
        if (parts.host.length > 0) domain = parts.host;
    }
    return [domain stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"."]];
}

static BOOL IsValidDomain(NSString *domain) {
    if (domain.length == 0 || domain.length > 253 || ![domain containsString:@"."] || [domain containsString:@".."]) return NO;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$" options:0 error:nil];
    return [regex firstMatchInString:domain options:0 range:NSMakeRange(0, domain.length)] != nil;
}

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property NSWindow *window;
@property NSMutableArray<NSString *> *domains;
@property NSArray<NSString *> *visibleDomains;
@property NSTableView *tableView;
@property NSTextField *inputField;
@property NSSearchField *searchField;
@property NSTextField *countLabel;
@property NSTextField *inputMessage;
@property NSTextView *logView;
@property NSTextField *statusLabel;
@property NSView *statusDot;
@property NSButton *runButton;
@property NSButton *removeRoutesButton;
@property NSProgressIndicator *progress;
@property BOOL running;
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    [self loadDomains];
    [self buildWindow];
    [self refreshVisibleDomains];
    [self setLog:@"Готово к работе. Подключите OpenVPN, затем нажмите «Запустить обход»." state:0];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

- (NSURL *)domainsURL {
    NSURL *base = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
    return [[base URLByAppendingPathComponent:@"VPN Bypass" isDirectory:YES] URLByAppendingPathComponent:@"domains.json"];
}

- (void)loadDomains {
    NSData *data = [NSData dataWithContentsOfURL:self.domainsURL];
    NSArray *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    self.domains = [(saved.count > 0 ? saved : DefaultDomains()) mutableCopy];
    [self sortDomains];
}

- (void)saveDomains {
    NSURL *directory = [self.domainsURL URLByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.domains options:NSJSONWritingPrettyPrinted error:nil];
    [data writeToURL:self.domainsURL options:NSDataWritingAtomic error:nil];
}

- (void)sortDomains {
    [self.domains sortUsingSelector:@selector(localizedStandardCompare:)];
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    return label;
}

- (void)buildWindow {
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 940, 650)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"VPN Bypass";
    self.window.minSize = NSMakeSize(820, 560);
    [self.window center];

    NSView *root = self.window.contentView;
    root.wantsLayer = YES;

    NSView *header = [[NSView alloc] init];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:header];

    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:@"arrow.triangle.branch" accessibilityDescription:nil]];
    icon.contentTintColor = NSColor.controlAccentColor;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:icon];

    NSTextField *title = [self label:@"VPN Bypass" size:22 weight:NSFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:title];
    NSTextField *subtitle = [self label:@"Маршруты выбранных доменов в обход OpenVPN" size:13 weight:NSFontWeightRegular];
    subtitle.textColor = NSColor.secondaryLabelColor;
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:subtitle];

    self.statusDot = [[NSView alloc] init];
    self.statusDot.wantsLayer = YES;
    self.statusDot.layer.cornerRadius = 4;
    self.statusDot.layer.backgroundColor = NSColor.secondaryLabelColor.CGColor;
    self.statusDot.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.statusDot];
    self.statusLabel = [self label:@"Ожидание" size:13 weight:NSFontWeightMedium];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [header addSubview:self.statusLabel];

    NSSplitView *split = [[NSSplitView alloc] init];
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:split];
    NSView *left = [self buildDomainPanel];
    NSView *right = [self buildLogPanel];
    [split addArrangedSubview:left];
    [split addArrangedSubview:right];
    [left.widthAnchor constraintGreaterThanOrEqualToConstant:360].active = YES;
    [right.widthAnchor constraintGreaterThanOrEqualToConstant:380].active = YES;

    NSView *footer = [self buildFooter];
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:root.topAnchor],
        [header.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [header.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [header.heightAnchor constraintEqualToConstant:82],
        [icon.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20],
        [icon.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [icon.widthAnchor constraintEqualToConstant:42], [icon.heightAnchor constraintEqualToConstant:42],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:14],
        [title.topAnchor constraintEqualToAnchor:header.topAnchor constant:19],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:3],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20],
        [self.statusLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [self.statusDot.trailingAnchor constraintEqualToAnchor:self.statusLabel.leadingAnchor constant:-8],
        [self.statusDot.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.statusDot.widthAnchor constraintEqualToConstant:8], [self.statusDot.heightAnchor constraintEqualToConstant:8],
        [split.topAnchor constraintEqualToAnchor:header.bottomAnchor],
        [split.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [split.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [split.bottomAnchor constraintEqualToAnchor:footer.topAnchor],
        [footer.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [footer.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [footer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor],
        [footer.heightAnchor constraintEqualToConstant:76]
    ]];
    [split setPosition:430 ofDividerAtIndex:0];
}

- (NSView *)buildDomainPanel {
    NSView *panel = [[NSView alloc] init];
    NSTextField *heading = [self label:@"Домены" size:15 weight:NSFontWeightSemibold];
    self.countLabel = [self label:@"0" size:13 weight:NSFontWeightRegular];
    self.countLabel.textColor = NSColor.secondaryLabelColor;

    NSButton *reset = [NSButton buttonWithTitle:@"Исходный список" target:self action:@selector(resetDefaults:)];
    reset.bezelStyle = NSBezelStyleInline;
    self.inputField = [NSTextField textFieldWithString:@""];
    self.inputField.placeholderString = @"example.com";
    self.inputField.delegate = self;
    NSButton *add = [NSButton buttonWithTitle:@"+" target:self action:@selector(addDomains:)];
    add.bezelStyle = NSBezelStyleTexturedRounded;
    self.inputMessage = [self label:@"Можно вставить несколько доменов" size:11 weight:NSFontWeightRegular];
    self.inputMessage.textColor = NSColor.secondaryLabelColor;
    self.searchField = [[NSSearchField alloc] init];
    self.searchField.placeholderString = @"Поиск";
    self.searchField.target = self;
    self.searchField.action = @selector(searchChanged:);
    self.searchField.sendsSearchStringImmediately = YES;

    self.tableView = [[NSTableView alloc] init];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"domain"];
    column.title = @"Домен";
    [self.tableView addTableColumn:column];
    self.tableView.headerView = nil;
    self.tableView.rowSizeStyle = NSTableViewRowSizeStyleMedium;
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.allowsMultipleSelection = YES;
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = self.tableView;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSButton *deleteButton = [NSButton buttonWithTitle:@"Удалить выбранные" target:self action:@selector(deleteSelected:)];
    deleteButton.bezelStyle = NSBezelStyleInline;

    NSArray *views = @[heading, self.countLabel, reset, self.inputField, add, self.inputMessage, self.searchField, scroll, deleteButton];
    for (NSView *view in views) { view.translatesAutoresizingMaskIntoConstraints = NO; [panel addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [heading.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16], [heading.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [self.countLabel.leadingAnchor constraintEqualToAnchor:heading.trailingAnchor constant:8], [self.countLabel.centerYAnchor constraintEqualToAnchor:heading.centerYAnchor],
        [reset.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16], [reset.centerYAnchor constraintEqualToAnchor:heading.centerYAnchor],
        [self.inputField.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:14], [self.inputField.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [add.leadingAnchor constraintEqualToAnchor:self.inputField.trailingAnchor constant:8], [add.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [add.centerYAnchor constraintEqualToAnchor:self.inputField.centerYAnchor], [add.widthAnchor constraintEqualToConstant:36],
        [self.inputMessage.topAnchor constraintEqualToAnchor:self.inputField.bottomAnchor constant:4], [self.inputMessage.leadingAnchor constraintEqualToAnchor:self.inputField.leadingAnchor],
        [self.searchField.topAnchor constraintEqualToAnchor:self.inputMessage.bottomAnchor constant:10], [self.searchField.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16], [self.searchField.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [scroll.topAnchor constraintEqualToAnchor:self.searchField.bottomAnchor constant:10], [scroll.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16], [scroll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [scroll.bottomAnchor constraintEqualToAnchor:deleteButton.topAnchor constant:-8],
        [deleteButton.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16], [deleteButton.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-12]
    ]];
    return panel;
}

- (NSView *)buildLogPanel {
    NSView *panel = [[NSView alloc] init];
    NSTextField *heading = [self label:@"Журнал" size:15 weight:NSFontWeightSemibold];
    NSButton *copy = [NSButton buttonWithTitle:@"Копировать" target:self action:@selector(copyLog:)];
    copy.bezelStyle = NSBezelStyleInline;
    self.logView = [[NSTextView alloc] init];
    self.logView.editable = NO;
    self.logView.selectable = YES;
    self.logView.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.logView.textContainerInset = NSMakeSize(12, 12);
    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.documentView = self.logView;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    NSTextField *hint = [self label:@"ⓘ OpenVPN подключают до запуска. После смены сети или IP запустите обход снова." size:11 weight:NSFontWeightRegular];
    hint.textColor = NSColor.secondaryLabelColor;
    hint.maximumNumberOfLines = 2;
    hint.lineBreakMode = NSLineBreakByWordWrapping;
    for (NSView *view in @[heading, copy, scroll, hint]) { view.translatesAutoresizingMaskIntoConstraints = NO; [panel addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [heading.topAnchor constraintEqualToAnchor:panel.topAnchor constant:16], [heading.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [copy.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16], [copy.centerYAnchor constraintEqualToAnchor:heading.centerYAnchor],
        [scroll.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:14], [scroll.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16], [scroll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
        [scroll.bottomAnchor constraintEqualToAnchor:hint.topAnchor constant:-12],
        [hint.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16], [hint.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16], [hint.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-15]
    ]];
    return panel;
}

- (NSView *)buildFooter {
    NSView *footer = [[NSView alloc] init];
    NSTextField *hint = [self label:@"🔒 Изменение маршрутов требует пароль администратора" size:11 weight:NSFontWeightRegular];
    hint.textColor = NSColor.secondaryLabelColor;
    self.removeRoutesButton = [NSButton buttonWithTitle:@"Удалить маршруты" target:self action:@selector(removeRoutes:)];
    self.runButton = [NSButton buttonWithTitle:@"▶  Запустить обход" target:self action:@selector(runBypass:)];
    self.runButton.bezelStyle = NSBezelStyleRounded;
    self.runButton.keyEquivalent = @"\r";
    self.progress = [[NSProgressIndicator alloc] init];
    self.progress.style = NSProgressIndicatorStyleSpinning;
    self.progress.controlSize = NSControlSizeSmall;
    self.progress.hidden = YES;
    for (NSView *view in @[hint, self.removeRoutesButton, self.runButton, self.progress]) { view.translatesAutoresizingMaskIntoConstraints = NO; [footer addSubview:view]; }
    [NSLayoutConstraint activateConstraints:@[
        [hint.leadingAnchor constraintEqualToAnchor:footer.leadingAnchor constant:18], [hint.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [self.runButton.trailingAnchor constraintEqualToAnchor:footer.trailingAnchor constant:-18], [self.runButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor], [self.runButton.widthAnchor constraintGreaterThanOrEqualToConstant:160],
        [self.removeRoutesButton.trailingAnchor constraintEqualToAnchor:self.runButton.leadingAnchor constant:-12], [self.removeRoutesButton.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor],
        [self.progress.trailingAnchor constraintEqualToAnchor:self.runButton.leadingAnchor constant:-9], [self.progress.centerYAnchor constraintEqualToAnchor:footer.centerYAnchor]
    ]];
    return footer;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.visibleDomains.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSTextField *cell = [tableView makeViewWithIdentifier:@"DomainCell" owner:self];
    if (!cell) {
        cell = [NSTextField labelWithString:@""];
        cell.identifier = @"DomainCell";
        cell.font = [NSFont systemFontOfSize:13];
    }
    cell.stringValue = [NSString stringWithFormat:@"◎   %@", self.visibleDomains[row]];
    return cell;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.inputField && [notification.userInfo[@"NSTextMovement"] integerValue] == NSReturnTextMovement) [self addDomains:nil];
}

- (void)refreshVisibleDomains {
    NSString *query = self.searchField.stringValue.lowercaseString;
    if (query.length == 0) self.visibleDomains = [self.domains copy];
    else self.visibleDomains = [self.domains filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString *domain, NSDictionary *bindings) { return [domain containsString:query]; }]];
    self.countLabel.stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)self.domains.count];
    [self.tableView reloadData];
}

- (void)searchChanged:(id)sender { [self refreshVisibleDomains]; }

- (void)addDomains:(id)sender {
    NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" ,;\n\t\r"];
    NSArray *parts = [self.inputField.stringValue componentsSeparatedByCharactersInSet:separators];
    NSInteger added = 0;
    NSMutableArray *rejected = [NSMutableArray array];
    for (NSString *part in parts) {
        NSString *domain = NormalizeDomain(part);
        if (domain.length == 0) continue;
        if (!IsValidDomain(domain)) { [rejected addObject:domain]; continue; }
        if (![self.domains containsObject:domain]) { [self.domains addObject:domain]; added++; }
    }
    if (added > 0) {
        [self sortDomains]; [self saveDomains]; [self refreshVisibleDomains];
        self.inputField.stringValue = @"";
        self.inputMessage.stringValue = [NSString stringWithFormat:@"Добавлено: %ld", (long)added];
        self.inputMessage.textColor = NSColor.secondaryLabelColor;
    } else if (rejected.count > 0) {
        self.inputMessage.stringValue = [NSString stringWithFormat:@"Некорректный домен: %@", [rejected componentsJoinedByString:@", "]];
        self.inputMessage.textColor = NSColor.systemRedColor;
    } else {
        self.inputMessage.stringValue = @"Такой домен уже есть.";
        self.inputMessage.textColor = NSColor.secondaryLabelColor;
    }
}

- (void)deleteSelected:(id)sender {
    NSIndexSet *indexes = self.tableView.selectedRowIndexes;
    NSMutableSet *toRemove = [NSMutableSet set];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) { if (idx < self.visibleDomains.count) [toRemove addObject:self.visibleDomains[idx]]; }];
    [self.domains removeObjectsInArray:toRemove.allObjects];
    [self saveDomains]; [self refreshVisibleDomains];
}

- (void)resetDefaults:(id)sender {
    self.domains = [DefaultDomains() mutableCopy]; [self sortDomains]; [self saveDomains]; [self refreshVisibleDomains];
    [self setLog:[NSString stringWithFormat:@"Восстановлен исходный список: %lu доменов.", (unsigned long)self.domains.count] state:0];
}

- (void)copyLog:(id)sender {
    [[NSPasteboard generalPasteboard] clearContents];
    [[NSPasteboard generalPasteboard] setString:self.logView.string forType:NSPasteboardTypeString];
}

- (void)runBypass:(id)sender { [self executeRemove:NO]; }
- (void)removeRoutes:(id)sender { [self executeRemove:YES]; }

- (void)executeRemove:(BOOL)remove {
    if (self.running || (!remove && self.domains.count == 0)) return;
    [self saveDomains];
    self.running = YES;
    self.runButton.enabled = NO; self.removeRoutesButton.enabled = NO;
    self.progress.hidden = NO; [self.progress startAnimation:nil];
    [self setLog:(remove ? @"Запрашиваю права администратора и удаляю маршруты…" : @"Запрашиваю права администратора и настраиваю маршруты…") state:1];
    NSArray *domains = [self.domains copy];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *output = nil;
        BOOL success = [self runScriptRemove:remove domains:domains output:&output];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.running = NO;
            self.runButton.enabled = YES; self.removeRoutesButton.enabled = YES;
            self.progress.hidden = YES; [self.progress stopAnimation:nil];
            [self setLog:output state:(success ? 2 : 3)];
        });
    });
}

- (BOOL)runScriptRemove:(BOOL)remove domains:(NSArray<NSString *> *)domains output:(NSString **)output {
    NSString *runner = [[NSBundle mainBundle] pathForResource:@"vpn-bypass-runner" ofType:@"sh"];
    if (!runner) { *output = @"В приложении не найден runner-скрипт."; return NO; }
    NSString *temporaryDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"vpn-bypass-%@", NSUUID.UUID.UUIDString]];
    NSString *domainsPath = [temporaryDirectory stringByAppendingPathComponent:@"domains.txt"];
    [[NSFileManager defaultManager] createDirectoryAtPath:temporaryDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0700} error:nil];
    NSString *content = [[domains componentsJoinedByString:@"\n"] stringByAppendingString:@"\n"];
    if (![content writeToFile:domainsPath atomically:YES encoding:NSUTF8StringEncoding error:nil]) { *output = @"Не удалось подготовить список доменов."; return NO; }
    NSString *command = remove ? [NSString stringWithFormat:@"%@ --remove", ShellQuote(runner)] : [NSString stringWithFormat:@"%@ --domains-file %@", ShellQuote(runner), ShellQuote(domainsPath)];
    NSString *source = [NSString stringWithFormat:@"do shell script %@ with administrator privileges", AppleScriptQuote(command)];
    NSAppleScript *script = [[NSAppleScript alloc] initWithSource:source];
    NSDictionary *error = nil;
    NSAppleEventDescriptor *result = [script executeAndReturnError:&error];
    [[NSFileManager defaultManager] removeItemAtPath:temporaryDirectory error:nil];
    if (error) {
        if ([error[NSAppleScriptErrorNumber] integerValue] == -128) *output = @"Операция отменена: права администратора не предоставлены.";
        else *output = [NSString stringWithFormat:@"Ошибка запуска:\n%@", error[NSAppleScriptErrorMessage] ?: @"Неизвестная ошибка"];
        return NO;
    }
    *output = result.stringValue.length > 0 ? result.stringValue : @"Операция завершена.";
    return YES;
}

- (void)setLog:(NSString *)text state:(NSInteger)state {
    self.logView.string = text ?: @"";
    NSArray *labels = @[@"Ожидание", @"Выполняется", @"Готово", @"Ошибка"];
    NSArray *colors = @[NSColor.secondaryLabelColor, NSColor.systemOrangeColor, NSColor.systemGreenColor, NSColor.systemRedColor];
    self.statusLabel.stringValue = labels[state];
    self.statusDot.layer.backgroundColor = ((NSColor *)colors[state]).CGColor;
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        [app run];
    }
    return 0;
}
