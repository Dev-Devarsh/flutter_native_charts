#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_native_charts.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_native_charts'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  # `*.metal` is compiled offline by Xcode when the Metal Toolchain is installed
  # (embeds default.metallib). No runtime `makeLibrary(source:)`.
  s.source_files = 'Classes/**/*.{h,cpp,mm,swift,metal}'
  s.public_header_files = 'Classes/ViewportEngineBridge.h', 'Classes/ChartEngineBridge.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.frameworks = 'Metal', 'MetalKit'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_native_charts_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
