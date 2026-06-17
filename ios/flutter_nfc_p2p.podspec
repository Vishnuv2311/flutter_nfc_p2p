Pod::Spec.new do |s|
  s.name             = 'flutter_nfc_p2p'
  s.version          = '0.1.0'
  s.summary          = 'Flutter plugin for custom NFC phone-to-phone communication (HCE + Reader).'
  s.description      = <<-DESC
    Headless Flutter plugin for closed-loop NFC payment handshakes.
    Uses CoreNFC for reader mode on iOS. HCE requires the iOS 18.1+
    Contactless entitlement (see README).
  DESC
  s.homepage         = 'https://github.com/your-org/flutter_nfc_p2p'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Org' => 'dev@your-org.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
