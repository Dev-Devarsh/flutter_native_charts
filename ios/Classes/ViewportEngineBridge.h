#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Phase 5: Obj-C facade over the C++ `ViewportEngine`. Swift code in the
/// plugin (gesture handlers, renderer) talks to this class so we don't have to
/// expose C++ class declarations to the Swift compiler.
///
/// Two construction modes:
///  - `init`: creates and owns a fresh ViewportEngine. Destroys it on dealloc.
///  - `initWithHandle:owns:NO`: wraps an existing ViewportEngine pointer (e.g.
///    one owned by `ChartEngineBridge`). Does NOT destroy on dealloc.
@interface ViewportEngineBridge : NSObject

- (instancetype)init;

- (instancetype)initWithHandle:(intptr_t)handle
                          owns:(BOOL)owns NS_DESIGNATED_INITIALIZER;

- (void)setDataBoundsWithXMin:(double)xMin
                         xMax:(double)xMax
                         yMin:(double)yMin
                         yMax:(double)yMax;

- (void)panNDCWithDx:(double)dxNDC dy:(double)dyNDC;

- (void)zoomNDCWithScaleX:(double)scaleX
                   scaleY:(double)scaleY
                   focusX:(double)focusXNDC
                   focusY:(double)focusYNDC;

- (void)reset;

/// Writes a column-major 4x4 projection matrix into [out16] (16 floats).
- (void)getProjectionMatrix:(float * _Nonnull)out16;

/// Monotonically increments on every mutating op.
- (long long)revision;

/// Writes [xMin, xMax] to caller-provided pointers.
- (void)getVisibleDomain:(double * _Nonnull)xMin xMax:(double * _Nonnull)xMax;

/// Writes [yMin, yMax] to caller-provided pointers.
- (void)getVisibleRange:(double * _Nonnull)yMin yMax:(double * _Nonnull)yMax;

@end

NS_ASSUME_NONNULL_END
