Pod::Spec.new do |s|
  s.name             = 'cliploop_highlights'
  s.version          = '0.1.0'
  s.summary          = 'On-device music separation + song highlight detection.'
  s.description      = 'UVR MDX-Net separation and prelude/interlude/postlude detection. NPU on Android; Core ML on iOS.'
  s.homepage         = 'https://github.com/swarooppatil12/Cliploop'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'Cliploop' => 'noreply@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
