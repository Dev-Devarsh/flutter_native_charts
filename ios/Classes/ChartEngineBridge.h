#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Obj-C facade over the C++ chart engine. Lets Swift call the extern-C API
/// without having to import C++ headers.
///
/// The bridge OWNS the underlying engine and frees it on dealloc.
@interface ChartEngineBridge : NSObject

@property(nonatomic, readonly) intptr_t handle;
@property(nonatomic, readonly) intptr_t viewportHandle;

- (instancetype)init;

// -- Series --
- (void)setSeriesType:(int)type;
- (int)seriesType;

// -- Generation / passes --
- (int)generation;
- (int)passCount;
- (long long)viewportRevision;
/// Rebuilds GPU meshes using the visible viewport so line strokes stay welded when zoomed.
- (void)rebuildGeometryForViewport;
- (int)readPass:(int)pass
   outPrimitive:(int * _Nullable)outPrimitive
    outVertices:(float * _Nullable)outVertices
       capacity:(int)capacityInFloats;

// -- Data --
- (void)pushCandlesRaw:(const double *)data count:(int)count;
- (void)appendCandlesRaw:(const double *)data count:(int)count;
- (int)candleCount;
/// Writes [t,o,h,l,c,v] into out6. Returns 1 if index in bounds, 0 otherwise.
- (int)getCandle:(int)index out6:(double *)out6;
- (void)getDataBoundsOut4:(double *)out4;

// -- Hit-test + hover --
- (int)hitTest:(double)xData;
- (void)setHover:(int)index;
- (int)hover;

// -- Ticks (writes up to maxCount, returns total available) --
- (int)getXTicks:(double * _Nullable)out maxCount:(int)maxCount;
- (int)getYTicks:(double * _Nullable)out maxCount:(int)maxCount;

// -- Projection --
- (void)projectX:(const double *)inX count:(int)count outNdc:(double *)outNdc;
- (void)projectY:(const double *)inY count:(int)count outNdc:(double *)outNdc;
- (double)unprojectX:(double)xNdc;
- (double)unprojectY:(double)yNdc;

// -- Trade lines (two-point segments) --
- (void)setTradeLineDraftActive:(BOOL)active
                             x1:(double)x1 y1:(double)y1
                             x2:(double)x2 y2:(double)y2;
- (void)notifyTradeLineDrawEndWithX1:(double)x1 y1:(double)y1 x2:(double)x2 y2:(double)y2;
- (long long)tradeLineDrawCancelRevision;

// -- Style --
/// Updates the engine's ChartStyle from a flat Swift representation.
///
/// `floats` MUST contain at least 54 floats and `ints` at least 10 ints (14 for
/// pan/zoom interaction flags); layout matches `chart_engine_jni.cpp` /
/// Dart `NativeChartStyle`. `seriesLabel` is UTF-8 in ChartStyle (≤31 chars).
- (void)setStyleFloats:(const float *)floats floatCount:(int)floatCount
                  ints:(const int *)ints intCount:(int)intCount
           seriesLabel:(NSString * _Nullable)seriesLabel;

/// Monotonic counter; bumps on every successful setStyle. Native overlay
/// reads this each frame and re-snapshots when it changes.
- (long long)styleRevision;

/// Fills `out` with 54 floats describing the engine's current style.
- (void)getStyleFloats:(float *)out floatCount:(int)floatCount;
/// Fills `out` with 14 ints describing toggles, tick/format ints, and interaction flags.
- (void)getStyleInts:(int *)out intCount:(int)intCount;
/// Returns the engine's series label as a Swift string.
- (NSString *)seriesLabel;

@end

NS_ASSUME_NONNULL_END
