#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <mach-o/dyld.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <vector>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <mutex>
#include <algorithm>

namespace Offsets {
    constexpr uintptr_t Camera_GetMain             = 0x3A24110;
    constexpr uintptr_t Camera_WorldToViewport     = 0x3A23980;
    constexpr uintptr_t Component_GetTransform     = 0x3A31040;
    constexpr uintptr_t Transform_GetPosition      = 0x3A45210;
    constexpr uintptr_t MatchGame_StaticClass      = 0x4B89120;
    constexpr uintptr_t MatchGame_PlayerDict       = 0x78;
    constexpr uintptr_t MatchGame_LocalPlayer      = 0x90;
    constexpr uintptr_t Player_GetCurHP            = 0x2104B10;
    constexpr uintptr_t Player_GetMaxHP            = 0x2104B80;
    constexpr uintptr_t Player_IsLocalTeammate     = 0x2108C40;
    constexpr uintptr_t Player_IsDead              = 0x2105110;
    constexpr uintptr_t Player_GetHeadTF           = 0x210F330;
    constexpr uintptr_t Player_GetHipTF            = 0x210F410;
}

static uintptr_t g_FrameworkBase = 0;
static bool g_EnableESP          = true;
static bool g_EnableLine         = true;
static bool g_EnableHealth       = true;
static bool g_IgnoreTeammate     = true;
static bool g_BypassActive       = true;

bool IsValidPtr(uintptr_t ptr) {
    if (ptr < 0x100000000ULL || ptr > 0x300000000ULL) return false;
    vm_size_t outSize = 0;
    uint8_t buf[8];
    kern_return_t kr = vm_read_overwrite(mach_task_self(), (vm_address_t)ptr, sizeof(uintptr_t), (vm_address_t)buf, &outSize);
    return (kr == KERN_SUCCESS && outSize == sizeof(uintptr_t));
}

template <typename T>
T ReadMem(uintptr_t address) {
    T val{};
    if (!IsValidPtr(address)) return val;
    vm_size_t outSize = 0;
    vm_read_overwrite(mach_task_self(), (vm_address_t)address, sizeof(T), (vm_address_t)&val, &outSize);
    return val;
}

uintptr_t GetFrameworkBase() {
    if (g_FrameworkBase != 0) return g_FrameworkBase;
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char* name = _dyld_get_image_name(i);
        if (name && strstr(name, "UnityFramework.framework/UnityFramework")) {
            g_FrameworkBase = (uintptr_t)_dyld_get_image_header(i);
            return g_FrameworkBase;
        }
    }
    g_FrameworkBase = (uintptr_t)_dyld_get_image_header(0);
    return g_FrameworkBase;
}

template <typename T>
T ResolveFn(uintptr_t offset) {
    uintptr_t base = GetFrameworkBase();
    if (!base || !offset) return nullptr;
    return reinterpret_cast<T>(base + offset);
}

@interface ACTelemetryBlocker : NSURLProtocol
@end

@implementation ACTelemetryBlocker
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {
    if (!g_BypassActive) return NO;
    NSString *url = request.URL.absoluteString.lowercaseString;
    if ([url containsString:@"crashlytics"] || [url containsString:@"app-measurement"] ||
        [url containsString:@"anticheat"] || [url containsString:@"security_report"] ||
        [url containsString:@"log_upload"]) {
        return YES;
    }
    return NO;
}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    NSHTTPURLResponse *res = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"application/json"}];
    [self.client URLProtocol:self didReceiveResponse:res cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[@"{"status":0}" dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

void ScrubOfflineBanLogs() {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray<NSString *> *dirs = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"],
        [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Caches"],
        NSTemporaryDirectory()
    ];
    NSArray<NSString *> *flaggedKeywords = @[@"crash", @"anr", @"log", @"report", @"tss_tmp", @"gg_report", @"ff_ac"];
    for (NSString *dir in dirs) {
        NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:dir error:nil];
        for (NSString *file in files) {
            NSString *lower = file.lowercaseString;
            for (NSString *kw in flaggedKeywords) {
                if ([lower containsString:kw]) {
                    [fm removeItemAtPath:[dir stringByAppendingPathComponent:file] error:nil];
                    break;
                }
            }
        }
    }
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"CACHED_LOG_ENABLE"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

struct Vector3 {
    float x, y, z;
    Vector3() : x(0), y(0), z(0) {}
    Vector3(float _x, float _y, float _z) : x(_x), y(_y), z(_z) {}
};

struct ESPTarget {
    CGPoint headScreen;
    CGPoint footScreen;
    int curHP;
    int maxHP;
};

void* GetMainCamera() {
    auto fn = ResolveFn<void*(*)()>(Offsets::Camera_GetMain);
    return fn ? fn() : nullptr;
}

Vector3 WorldToViewport(void* cam, Vector3 worldPos) {
    auto fn = ResolveFn<Vector3(*)(void*, Vector3)>(Offsets::Camera_WorldToViewport);
    return (fn && cam) ? fn(cam, worldPos) : Vector3(0, 0, -1);
}

Vector3 GetTransformPosition(void* transform) {
    auto fn = ResolveFn<Vector3(*)(void*)>(Offsets::Transform_GetPosition);
    return (fn && transform) ? fn(transform) : Vector3();
}

void* GetComponentTransform(void* component) {
    auto fn = ResolveFn<void*(*)(void*)>(Offsets::Component_GetTransform);
    return (fn && component) ? fn(component) : nullptr;
}

bool IsTeammate(void* player) {
    auto fn = ResolveFn<bool(*)(void*)>(Offsets::Player_IsLocalTeammate);
    return (fn && player) ? fn(player) : false;
}

bool IsDead(void* player) {
    auto fn = ResolveFn<bool(*)(void*)>(Offsets::Player_IsDead);
    return (fn && player) ? fn(player) : true;
}

int GetCurHP(void* player) {
    auto fn = ResolveFn<int(*)(void*)>(Offsets::Player_GetCurHP);
    return (fn && player) ? fn(player) : 0;
}

int GetMaxHP(void* player) {
    auto fn = ResolveFn<int(*)(void*)>(Offsets::Player_GetMaxHP);
    return (fn && player) ? fn(player) : 200;
}

Vector3 GetPlayerBonePos(void* player, uintptr_t boneMethodOffset, float fallbackOffsetY) {
    auto fn = ResolveFn<void*(*)(void*)>(boneMethodOffset);
    if (fn && IsValidPtr((uintptr_t)player)) {
        void* boneTF = fn(player);
        if (IsValidPtr((uintptr_t)boneTF)) return GetTransformPosition(boneTF);
    }
    void* rootTF = GetComponentTransform(player);
    Vector3 pos = IsValidPtr((uintptr_t)rootTF) ? GetTransformPosition(rootTF) : Vector3();
    pos.y += fallbackOffsetY;
    return pos;
}

std::vector<void*> ReadMatchPlayers(void*& outLocalPlayer) {
    std::vector<void*> result;
    outLocalPlayer = nullptr;
    uintptr_t base = GetFrameworkBase();
    if (!base) return result;

    uintptr_t matchGamePtr = ReadMem<uintptr_t>(base + Offsets::MatchGame_StaticClass);
    if (!IsValidPtr(matchGamePtr)) return result;

    outLocalPlayer = ReadMem<void*>(matchGamePtr + Offsets::MatchGame_LocalPlayer);
    uintptr_t dictPtr = ReadMem<uintptr_t>(matchGamePtr + Offsets::MatchGame_PlayerDict);
    if (!IsValidPtr(dictPtr)) return result;

    uintptr_t entriesArr = ReadMem<uintptr_t>(dictPtr + 0x18);
    int32_t count = ReadMem<int32_t>(dictPtr + 0x20);
    if (!IsValidPtr(entriesArr) || count <= 0 || count > 64) return result;

    for (int32_t i = 0; i < count; i++) {
        uintptr_t entryAddr = entriesArr + 0x20 + (i * 0x28);
        void* playerPtr = ReadMem<void*>(entryAddr + 0x20);
        if (IsValidPtr((uintptr_t)playerPtr)) result.push_back(playerPtr);
    }
    return result;
}

@interface ESPOverlayView : UIView
@property (nonatomic, assign) std::vector<ESPTarget> renderTargets;
@end

@implementation ESPOverlayView
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.opaque = NO;
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    if (!g_EnableESP || _renderTargets.empty()) return;
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    CGPoint topCenter = CGPointMake(rect.size.width * 0.5f, 0.0f);

    for (const auto& t : _renderTargets) {
        CGFloat boxH = std::fabs(t.footScreen.y - t.headScreen.y);
        CGFloat boxW = boxH * 0.52f;
        CGFloat boxX = t.headScreen.x - (boxW * 0.5f);
        CGFloat boxY = t.headScreen.y;

        if (g_EnableLine) {
            CGContextSetRGBStrokeColor(ctx, 1.0f, 0.12f, 0.12f, 0.88f);
            CGContextSetLineWidth(ctx, 1.2f);
            CGContextMoveToPoint(ctx, topCenter.x, topCenter.y);
            CGContextAddLineToPoint(ctx, t.headScreen.x, t.headScreen.y);
            CGContextStrokePath(ctx);
        }

        CGRect boxRect = CGRectMake(boxX, boxY, boxW, boxH);
        CGContextSetRGBStrokeColor(ctx, 1.0f, 0.0f, 0.0f, 0.92f);
        CGContextSetLineWidth(ctx, 1.3f);
        CGContextStrokeRect(ctx, boxRect);

        if (g_EnableHealth && t.maxHP > 0) {
            float ratio = std::clamp((float)t.curHP / (float)t.maxHP, 0.0f, 1.0f);
            CGFloat barW = 3.5f;
            CGFloat barX = boxX - barW - 3.0f;
            CGContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 0.65f);
            CGContextFillRect(ctx, CGRectMake(barX, boxY, barW, boxH));

            CGFloat fillH = boxH * ratio;
            CGFloat fillY = boxY + (boxH - fillH);
            CGFloat r = (ratio < 0.5f) ? 1.0f : (1.0f - (ratio - 0.5f) * 2.0f);
            CGFloat g = (ratio > 0.5f) ? 1.0f : (ratio * 2.0f);
            CGContextSetRGBFillColor(ctx, r, g, 0.1f, 0.95f);
            CGContextFillRect(ctx, CGRectMake(barX, fillY, barW, fillH));
        }
    }
}
@end

@interface ESPMenuController : NSObject
@property (nonatomic, strong) UIView *secureContainer;
@property (nonatomic, strong) ESPOverlayView *overlayView;
@property (nonatomic, strong) UIView *menuPanel;
@property (nonatomic, strong) UIButton *floatingBtn;
@property (nonatomic, strong) CADisplayLink *displayLink;
@end

@implementation ESPMenuController
+ (instancetype)shared {
    static ESPMenuController *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[ESPMenuController alloc] init]; });
    return inst;
}
- (void)setupUI {
    UIWindow *keyWindow = nil;
    for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *w in scene.windows) { if (w.isKeyWindow) { keyWindow = w; break; } }
        }
    }
    if (!keyWindow) return;

    UITextField *secureField = [[UITextField alloc] initWithFrame:keyWindow.bounds];
    secureField.secureTextEntry = YES;
    secureField.userInteractionEnabled = NO;
    UIView *stealthView = secureField.subviews.firstObject;
    if (!stealthView) stealthView = [[UIView alloc] initWithFrame:keyWindow.bounds];
    stealthView.frame = keyWindow.bounds;
    stealthView.userInteractionEnabled = NO;
    [keyWindow addSubview:stealthView];
    self.secureContainer = stealthView;

    self.overlayView = [[ESPOverlayView alloc] initWithFrame:keyWindow.bounds];
    [self.secureContainer addSubview:self.overlayView];

    self.floatingBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    self.floatingBtn.frame = CGRectMake(30, 80, 48, 48);
    self.floatingBtn.backgroundColor = [UIColor colorWithRed:0.08f green:0.06f blue:0.1f alpha:0.88f];
    self.floatingBtn.layer.cornerRadius = 24;
    self.floatingBtn.layer.borderWidth = 1.5f;
    self.floatingBtn.layer.borderColor = [UIColor greenColor].CGColor;
    [self.floatingBtn setTitle:@"SAFE" forState:UIControlStateNormal];
    self.floatingBtn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [self.floatingBtn addTarget:self action:@selector(toggleMenu) forControlEvents:UIControlEventTouchUpInside];
    [keyWindow addSubview:self.floatingBtn];

    self.menuPanel = [[UIView alloc] initWithFrame:CGRectMake(88, 80, 235, 215)];
    self.menuPanel.backgroundColor = [UIColor colorWithRed:0.06f green:0.06f blue:0.08f alpha:0.94f];
    self.menuPanel.layer.cornerRadius = 10;
    self.menuPanel.layer.borderWidth = 1.0f;
    self.menuPanel.layer.borderColor = [UIColor colorWithRed:0.2f green:0.9f blue:0.3f alpha:0.8f].CGColor;
    self.menuPanel.hidden = YES;

    [self addSwitchRow:@"ESP Xuyên Bụi Cỏ" y:12 tag:1 defaultVal:g_EnableESP];
    [self addSwitchRow:@"Tia Line Kẻ Địch" y:50 tag:2 defaultVal:g_EnableLine];
    [self addSwitchRow:@"Thanh Máu (HP Bar)" y:88 tag:3 defaultVal:g_EnableHealth];
    [self addSwitchRow:@"Bỏ Qua Đồng Đội" y:126 tag:4 defaultVal:g_IgnoreTeammate];
    [self addSwitchRow:@"Chống Ban Offline (Xóa Log)" y:164 tag:5 defaultVal:g_BypassActive];

    [keyWindow addSubview:self.menuPanel];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppCleanExit) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onAppCleanExit) name:UIApplicationWillTerminateNotification object:nil];

    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(onFrameTick)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}
- (void)addSwitchRow:(NSString *)title y:(CGFloat)y tag:(NSInteger)tag defaultVal:(BOOL)val {
    UILabel *lbl = [[UILabel alloc] initWithFrame:CGRectMake(12, y, 160, 30)];
    lbl.text = title;
    lbl.textColor = [UIColor whiteColor];
    lbl.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [self.menuPanel addSubview:lbl];

    UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectMake(175, y, 50, 30)];
    sw.on = val;
    sw.tag = tag;
    sw.transform = CGAffineTransformMakeScale(0.75f, 0.75f);
    sw.onTintColor = [UIColor colorWithRed:0.2f green:0.85f blue:0.3f alpha:1.0f];
    [sw addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.menuPanel addSubview:sw];
}
- (void)toggleMenu { self.menuPanel.hidden = !self.menuPanel.hidden; }
- (void)onSwitchChanged:(UISwitch *)sender {
    switch (sender.tag) {
        case 1: g_EnableESP = sender.isOn; break;
        case 2: g_EnableLine = sender.isOn; break;
        case 3: g_EnableHealth = sender.isOn; break;
        case 4: g_IgnoreTeammate = sender.isOn; break;
        case 5: g_BypassActive = sender.isOn; if (g_BypassActive) ScrubOfflineBanLogs(); break;
    }
}
- (void)onAppCleanExit { if (g_BypassActive) ScrubOfflineBanLogs(); }
- (void)onFrameTick {
    if (!g_EnableESP) {
        self.overlayView.renderTargets = {};
        [self.overlayView setNeedsDisplay];
        return;
    }
    void* cam = GetMainCamera();
    if (!IsValidPtr((uintptr_t)cam)) return;

    void* localPlayer = nullptr;
    std::vector<void*> players = ReadMatchPlayers(localPlayer);
    CGSize screen = self.overlayView.bounds.size;
    std::vector<ESPTarget> validTargets;

    for (void* player : players) {
        if (!player || player == localPlayer || IsDead(player)) continue;
        if (g_IgnoreTeammate && IsTeammate(player)) continue;

        int curHP = GetCurHP(player);
        int maxHP = GetMaxHP(player);
        if (curHP <= 0) continue;

        Vector3 headWorld = GetPlayerBonePos(player, Offsets::Player_GetHeadTF, 1.65f);
        headWorld.y += 0.2f;
        Vector3 footWorld = GetPlayerBonePos(player, Offsets::Player_GetHipTF, 0.0f);
        footWorld.y -= 0.9f;

        Vector3 headVP = WorldToViewport(cam, headWorld);
        Vector3 footVP = WorldToViewport(cam, footWorld);

        if (headVP.z > 0.1f && footVP.z > 0.1f) {
            ESPTarget target;
            target.headScreen = CGPointMake(headVP.x * screen.width, (1.0f - headVP.y) * screen.height);
            target.footScreen = CGPointMake(footVP.x * screen.width, (1.0f - footVP.y) * screen.height);
            target.curHP = curHP;
            target.maxHP = maxHP > 0 ? maxHP : 200;
            validTargets.push_back(target);
        }
    }
    self.overlayView.renderTargets = validTargets;
    [self.overlayView setNeedsDisplay];
}
@end

__attribute__((constructor))
static void InitSafeFFESP() {
    [NSURLProtocol registerClass:[ACTelemetryBlocker class]];
    ScrubOfflineBanLogs();
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[ESPMenuController shared] setupUI];
    });
}
