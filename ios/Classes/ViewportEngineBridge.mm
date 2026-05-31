#import "ViewportEngineBridge.h"

#include "viewport_engine.h"

@implementation ViewportEngineBridge {
  ViewportEngine* _engine;
  BOOL _owns;
}

- (instancetype)init {
  return [self initWithHandle:reinterpret_cast<intptr_t>(new ViewportEngine())
                          owns:YES];
}

- (instancetype)initWithHandle:(intptr_t)handle owns:(BOOL)owns {
  self = [super init];
  if (self) {
    _engine = reinterpret_cast<ViewportEngine*>(handle);
    _owns = owns;
  }
  return self;
}

- (void)dealloc {
  if (_owns && _engine != nullptr) {
    delete _engine;
    _engine = nullptr;
  }
}

- (void)setDataBoundsWithXMin:(double)xMin xMax:(double)xMax yMin:(double)yMin yMax:(double)yMax {
  if (_engine == nullptr) return;
  _engine->setDataBounds(xMin, xMax, yMin, yMax);
}

- (void)panNDCWithDx:(double)dxNDC dy:(double)dyNDC {
  if (_engine == nullptr) return;
  _engine->panNDC(dxNDC, dyNDC);
}

- (void)zoomNDCWithScaleX:(double)scaleX
                   scaleY:(double)scaleY
                   focusX:(double)focusXNDC
                   focusY:(double)focusYNDC {
  if (_engine == nullptr) return;
  _engine->zoomNDC(scaleX, scaleY, focusXNDC, focusYNDC);
}

- (void)reset {
  if (_engine == nullptr) return;
  _engine->reset();
}

- (void)getProjectionMatrix:(float *)out16 {
  if (_engine == nullptr || out16 == nullptr) return;
  _engine->getProjectionMatrix(out16);
}

- (long long)revision {
  if (_engine == nullptr) return 0;
  return _engine->revision();
}

- (void)getVisibleDomain:(double *)xMin xMax:(double *)xMax {
  if (_engine == nullptr) return;
  _engine->getVisibleDomain(xMin, xMax);
}

- (void)getVisibleRange:(double *)yMin yMax:(double *)yMax {
  if (_engine == nullptr) return;
  _engine->getVisibleRange(yMin, yMax);
}

@end
