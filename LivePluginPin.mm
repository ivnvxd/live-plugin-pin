#import <AppKit/AppKit.h>

#include "base/source/fstreamer.h"
#include "pluginterfaces/vst/ivstparameterchanges.h"
#include "public.sdk/source/main/pluginfactory.h"
#include "public.sdk/source/vst/vstaudioeffect.h"
#include "public.sdk/source/vst/vsteditcontroller.h"

#include <atomic>
#include <cstring>

@interface LivePinRecord : NSObject
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic) BOOL hidesOnDeactivate;
@property(nonatomic) NSWindowLevel level;
@property(nonatomic) BOOL reorderedInBackground;
@end
@implementation LivePinRecord
@end

static BOOL isLiveProcess() {
    static const BOOL inLive = [NSBundle.mainBundle.bundleIdentifier.lowercaseString
        hasPrefix:@"com.ableton.live"];
    return inLive;
}

static BOOL hasPluginWindowClass(id object) {
    return [NSStringFromClass([object class]) containsString:@"PluginCocoaWindow"];
}

@interface LivePinActivation : NSObject
- (void)setComponentActive:(BOOL)active;
- (void)setProcessing:(BOOL)processing;
- (BOOL)isProcessing;
- (void)setAboveLiveOnly:(BOOL)aboveLiveOnly;
- (BOOL)isAboveLiveOnly;
@end

@interface LivePinWindows : NSObject
- (void)setActive:(BOOL)active forInstance:(LivePinActivation *)instance;
@end

@implementation LivePinWindows {
    NSHashTable<LivePinActivation *> *_activeInstances;
    NSMutableArray<LivePinRecord *> *_pins;
    NSHashTable<NSWindow *> *_windowsAtDeactivation;
    NSTimer *_timer;
    NSUInteger _deactivation;
    NSTimeInterval _trackingResumesAt;
    BOOL _tracking;
    BOOL _foreground;
    BOOL _aboveLiveOnly;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _activeInstances = [NSHashTable weakObjectsHashTable];
        _pins = [NSMutableArray array];
        _windowsAtDeactivation = [NSHashTable weakObjectsHashTable];
    }
    return self;
}

- (void)setActive:(BOOL)active forInstance:(LivePinActivation *)instance {
    if (active) {
        [_activeInstances addObject:instance];
        [self startTimer];
    } else {
        [_activeInstances removeObject:instance];
        if (_activeInstances.count == 0) {
            [_timer invalidate];
            _timer = nil;
        }
    }
    [self tick];
}

- (void)updateTracking {
    BOOL shouldTrack = NO;
    BOOL aboveLiveOnly = YES;
    for (LivePinActivation *instance in _activeInstances) {
        if (instance.isProcessing) {
            shouldTrack = YES;
            aboveLiveOnly = aboveLiveOnly && instance.isAboveLiveOnly;
        }
    }
    if (shouldTrack && aboveLiveOnly != _aboveLiveOnly) {
        _aboveLiveOnly = aboveLiveOnly;
        if (_tracking && !NSApp.isActive) { [self restoreAfterDeactivation:_deactivation]; }
    }
    if (shouldTrack == _tracking) { return; }
    _tracking = shouldTrack;
    if (shouldTrack) {
        _trackingResumesAt = 0;
        [self observe];
    } else {
        [self stop];
    }
}

- (void)tick {
    [self updateTracking];
    [self synchronizeWindows];
}

- (void)observe {
    _foreground = NSApp.isActive;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    [center addObserver:self selector:@selector(willDeactivate:)
                   name:NSApplicationWillResignActiveNotification object:NSApp];
    [center addObserver:self selector:@selector(didDeactivate:)
                   name:NSApplicationDidResignActiveNotification object:NSApp];
    [center addObserver:self selector:@selector(didActivate:)
                   name:NSApplicationDidBecomeActiveNotification object:NSApp];
    [center addObserver:self selector:@selector(windowWillClose:)
                   name:NSWindowWillCloseNotification object:nil];
}

- (void)startTimer {
    if (_timer) { return; }
    __weak LivePinWindows *weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:0.15 repeats:YES block:^(NSTimer *timer) {
        [weakSelf tick];
    }];
    _timer.tolerance = 0.03;
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    _foreground = NO;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    ++_deactivation;
    for (LivePinRecord *pin in _pins.copy) { [self removePin:pin restoreVisibility:YES]; }
}

- (BOOL)isOpenEditor:(NSWindow *)window {
    if (!window.isVisible || window.isMiniaturized || window.sheetParent ||
        (window.styleMask & NSWindowStyleMaskFullScreen) || !window.contentView) {
        return NO;
    }
    return hasPluginWindowClass(window) ||
           hasPluginWindowClass(window.delegate) ||
           hasPluginWindowClass(window.nextResponder) ||
           hasPluginWindowClass(window.contentView.nextResponder);
}

- (LivePinRecord *)pinForWindow:(NSWindow *)window {
    if (!window) { return nil; }
    for (LivePinRecord *pin in _pins) {
        if (pin.window == window) { return pin; }
    }
    return nil;
}

- (void)pinWindow:(NSWindow *)window {
    LivePinRecord *pin = [[LivePinRecord alloc] init];
    pin.window = window;
    pin.level = window.level;
    pin.hidesOnDeactivate = window.hidesOnDeactivate;
    [_pins addObject:pin];
    window.hidesOnDeactivate = NO;
    window.level = MAX(window.level, NSFloatingWindowLevel);
}

- (void)removePin:(LivePinRecord *)pin restoreVisibility:(BOOL)restoreVisibility {
    NSWindow *window = pin.window;
    [_pins removeObject:pin];
    if (!window) { return; }
    [_windowsAtDeactivation removeObject:window];
    window.hidesOnDeactivate = pin.hidesOnDeactivate;
    window.level = pin.level;
    if (restoreVisibility && (pin.hidesOnDeactivate || pin.reorderedInBackground) && !NSApp.isActive) {
        [window orderOut:nil];
    }
}

- (void)synchronizeWindows {
    if (!_tracking || !_foreground || !NSApp.isActive ||
        NSProcessInfo.processInfo.systemUptime < _trackingResumesAt) {
        return;
    }
    for (LivePinRecord *pin in _pins.copy) {
        NSWindow *window = pin.window;
        if (!window || !window.isVisible || window.isMiniaturized) {
            [self removePin:pin restoreVisibility:NO];
        }
    }
    for (NSWindow *window in NSApp.windows) {
        if ([self isOpenEditor:window] && ![self pinForWindow:window]) {
            [self pinWindow:window];
        }
    }
}

- (void)windowWillClose:(NSNotification *)note {
    LivePinRecord *pin = [self pinForWindow:note.object];
    if (pin) {
        [self removePin:pin restoreVisibility:NO];
    }
}

- (void)willDeactivate:(NSNotification *)note {
    [self updateTracking];
    if (!_tracking) { return; }
    _foreground = NO;
    ++_deactivation;
    [_windowsAtDeactivation removeAllObjects];
    for (LivePinRecord *pin in _pins.copy) {
        NSWindow *window = pin.window;
        if (!window) {
            [_pins removeObject:pin];
        } else if (!window.isMiniaturized) {
            // Live can hide its editors in its own notification handler, ahead of ours.
            [_windowsAtDeactivation addObject:window];
        }
    }
}

- (void)didDeactivate:(NSNotification *)note {
    if (!_windowsAtDeactivation.count) { return; }
    const NSUInteger change = _deactivation;
    __weak LivePinWindows *weakSelf = self;

    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf restoreAfterDeactivation:change]; });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 160 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{ [weakSelf restoreAfterDeactivation:change]; });
}

- (NSWindow *)liveWindowBelowEditors {
    for (NSWindow *window in NSApp.orderedWindows) {
        if (window.isVisible && window.level == NSNormalWindowLevel && ![self pinForWindow:window]) {
            return window;
        }
    }
    return nil;
}

- (void)restoreAfterDeactivation:(NSUInteger)change {
    if (change != _deactivation || NSApp.isActive || NSApp.isHidden) { return; }
    NSWindow *anchor = _aboveLiveOnly ? [self liveWindowBelowEditors] : nil;
    for (NSWindow *window in _windowsAtDeactivation.allObjects) {
        LivePinRecord *pin = [self pinForWindow:window];
        if (!pin || window.isMiniaturized || !window.contentView) { continue; }
        if (!window.isVisible) { pin.reorderedInBackground = YES; }
        if (anchor) {
            // Other apps stay above the editor. Only Live's own window stays below it.
            window.level = NSNormalWindowLevel;
            [window orderWindow:NSWindowAbove relativeTo:anchor.windowNumber];
        } else {
            window.level = MAX(pin.level, NSFloatingWindowLevel);
            [window orderFrontRegardless];
        }
    }
}

- (void)didActivate:(NSNotification *)note {
    ++_deactivation;
    _foreground = YES;
    // Let Live settle its own window visibility before treating a hidden editor as dismissed.
    _trackingResumesAt = NSProcessInfo.processInfo.systemUptime + 0.17;
    for (LivePinRecord *pin in _pins) {
        pin.reorderedInBackground = NO;
        pin.window.level = MAX(pin.level, NSFloatingWindowLevel);
    }
}
@end

@implementation LivePinActivation {
    std::atomic_bool _processing;
    std::atomic_bool _aboveLiveOnly;
    BOOL _componentActive;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _processing.store(false, std::memory_order_relaxed);
        _aboveLiveOnly.store(true, std::memory_order_relaxed);
    }
    return self;
}

- (void)setAboveLiveOnly:(BOOL)aboveLiveOnly {
    // Set from the audio thread or from state. Poll it on the main thread.
    _aboveLiveOnly.store(aboveLiveOnly, std::memory_order_relaxed);
}

- (BOOL)isAboveLiveOnly {
    return _aboveLiveOnly.load(std::memory_order_relaxed);
}

- (void)setProcessing:(BOOL)processing {
    // Live uses this callback for the Device Activator. Poll it on the main thread.
    _processing.store(processing, std::memory_order_relaxed);
}

- (BOOL)isProcessing {
    return _processing.load(std::memory_order_relaxed);
}

- (void)setComponentActive:(BOOL)active {
    if (!isLiveProcess() || _componentActive == active) { return; }
    _componentActive = active;
    if (!active) { _processing.store(false, std::memory_order_relaxed); }
    // Multiple instances share one owner for the native window settings.
    static LivePinWindows *windows = [[LivePinWindows alloc] init];
    [windows setActive:active forInstance:self];
}
@end

namespace {
using namespace Steinberg;
using namespace Steinberg::Vst;
const FUID processorUID(0x185DC881, 0x3A5F4533, 0xB8DE35B9, 0x57885A1F);
const FUID controllerUID(0x2670B9AA, 0x959E4185, 0xA577F86E, 0x30805667);
constexpr ParamID kStayAboveId = 0;

// Sets saved before this parameter existed have no state. They keep the default, Live.
bool readStayAbove(IBStream* state, bool& aboveLiveOnly) {
    int32 value = 0;
    if (!state || !IBStreamer(state, kLittleEndian).readInt32(value)) { return false; }
    aboveLiveOnly = value != 0;
    return true;
}

class PassThrough final : public AudioEffect {
public:
    PassThrough() { setControllerClass(controllerUID); }
    ~PassThrough() override { [activation_ setComponentActive:NO]; }

    static FUnknown* create(void*) { return static_cast<IAudioProcessor*>(new PassThrough()); }

    tresult PLUGIN_API initialize(FUnknown* host) override {
        const auto result = AudioEffect::initialize(host);
        if (result != kResultOk) { return result; }

        addAudioInput(STR16("Input"), SpeakerArr::kStereo);
        addAudioOutput(STR16("Output"), SpeakerArr::kStereo);
        return kResultOk;
    }

    tresult PLUGIN_API setActive(TBool enabled) override {
        const auto result = AudioEffect::setActive(enabled);
        if (result == kResultOk) { [activation_ setComponentActive:enabled != 0]; }
        return result;
    }

    tresult PLUGIN_API setProcessing(TBool processing) override {
        [activation_ setProcessing:processing != 0];
        return kResultOk;
    }

    tresult PLUGIN_API terminate() override {
        [activation_ setComponentActive:NO];
        return AudioEffect::terminate();
    }

    tresult PLUGIN_API process(ProcessData& data) override {
        if (auto* changes = data.inputParameterChanges) {
            for (int32 index = 0; index < changes->getParameterCount(); ++index) {
                auto* queue = changes->getParameterData(index);
                int32 offset = 0;
                ParamValue value = 0;
                if (queue && queue->getParameterId() == kStayAboveId && queue->getPointCount() > 0 &&
                    queue->getPoint(queue->getPointCount() - 1, offset, value) == kResultOk) {
                    [activation_ setAboveLiveOnly:value >= 0.5];
                }
            }
        }
        if (data.numSamples <= 0 || data.numInputs != 1 || data.numOutputs != 1) {
            return kResultOk;
        }
        const auto& input = data.inputs[0];
        auto& output = data.outputs[0];
        const auto bytes = static_cast<size_t>(data.numSamples) * sizeof(Sample32);
        for (int32 channel = 0; channel < output.numChannels; ++channel) {
            auto* destination = output.channelBuffers32[channel];
            if (channel >= input.numChannels) {
                std::memset(destination, 0, bytes);
            } else if (input.channelBuffers32[channel] != destination) {
                std::memcpy(destination, input.channelBuffers32[channel], bytes);
            }
        }
        output.silenceFlags = input.silenceFlags;
        return kResultOk;
    }

    tresult PLUGIN_API getState(IBStream* state) override {
        const int32 value = activation_.isAboveLiveOnly ? 1 : 0;
        return IBStreamer(state, kLittleEndian).writeInt32(value) ? kResultOk : kResultFalse;
    }

    tresult PLUGIN_API setState(IBStream* state) override {
        bool aboveLiveOnly = true;
        readStayAbove(state, aboveLiveOnly);
        [activation_ setAboveLiveOnly:aboveLiveOnly];
        return kResultOk;
    }

private:
    LivePinActivation* __strong activation_ = [[LivePinActivation alloc] init];
};

class PinController final : public EditController {
public:
    static FUnknown* create(void*) { return static_cast<IEditController*>(new PinController()); }

    tresult PLUGIN_API initialize(FUnknown* context) override {
        const auto result = EditController::initialize(context);
        if (result != kResultOk) { return result; }

        auto* stayAbove = new StringListParameter(STR16("Stay Above"), kStayAboveId);
        stayAbove->appendString(STR16("All Apps"));
        stayAbove->appendString(STR16("Live"));
        stayAbove->getInfo().defaultNormalizedValue = 1.0;
        stayAbove->setNormalized(1.0);
        parameters.addParameter(stayAbove);
        return kResultOk;
    }

    tresult PLUGIN_API setComponentState(IBStream* state) override {
        bool aboveLiveOnly = true;
        readStayAbove(state, aboveLiveOnly);
        setParamNormalized(kStayAboveId, aboveLiveOnly ? 1.0 : 0.0);
        return kResultOk;
    }

    // Earlier versions saved a separate setting in the controller. Live now saves
    // the Device Activator itself. Accept either format when opening old sets.
    tresult PLUGIN_API setState(IBStream*) override { return kResultOk; }
    tresult PLUGIN_API getState(IBStream*) override { return kResultOk; }
};
} // namespace

using namespace Steinberg;
using namespace Steinberg::Vst;

BEGIN_FACTORY_DEF("ivnvxd", "https://github.com/ivnvxd/live-plugin-pin", "")
    DEF_CLASS2(INLINE_UID_FROM_FUID(processorUID), PClassInfo::kManyInstances,
               kVstAudioEffectClass, "Live Plugin Pin", 0, "Fx|Tools",
               PLUGIN_VERSION, kVstVersionString, PassThrough::create)
    DEF_CLASS2(INLINE_UID_FROM_FUID(controllerUID), PClassInfo::kManyInstances,
               kVstComponentControllerClass, "Live Plugin Pin Controller", 0, "",
               PLUGIN_VERSION, kVstVersionString, PinController::create)
END_FACTORY
