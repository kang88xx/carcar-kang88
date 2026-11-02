# QA-only standalone project, using the xcodeproj already pinned by fastlane.
require 'fileutils'
require 'xcodeproj'

root = File.expand_path('..', __dir__)
output = File.expand_path(ARGV.fetch(0))
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(File.join(output, 'IconAlertWatcher.xcodeproj'))
host = project.new_target(:application, 'AlertWatcherHost', :ios, '17.0')
tests = project.new_target(:ui_test_bundle, 'IconAlertWatcherTests', :ios, '17.0')
tests.add_dependency(host)
File.write(File.join(output, 'Host.swift'), <<~SWIFT)
  import UIKit
  @main final class HostDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ application: UIApplication, didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
      window = UIWindow(frame: UIScreen.main.bounds)
      window?.rootViewController = UIViewController()
      window?.makeKeyAndVisible()
      return true
    }
  }
SWIFT
host.add_file_references([project.main_group.new_file('Host.swift')])
FileUtils.cp(File.join(root, 'ios/QA/IconAlertWatcherTests.swift'), output)
tests.add_file_references([project.main_group.new_file('IconAlertWatcherTests.swift')])
[host, tests].each do |target|
  target.build_configurations.each do |configuration|
    configuration.build_settings.merge!({
      'PRODUCT_BUNDLE_IDENTIFIER' => "com.kang88.carcar.qa.#{target.name}",
      'PRODUCT_NAME' => '$(TARGET_NAME)',
      'SWIFT_VERSION' => '5.0',
      'GENERATE_INFOPLIST_FILE' => 'YES',
      'CODE_SIGNING_ALLOWED' => 'NO',
      'TARGETED_DEVICE_FAMILY' => '1',
      'SUPPORTED_PLATFORMS' => 'iphonesimulator',
      'SDKROOT' => 'iphonesimulator'
    })
  end
end
tests.build_configurations.each do |configuration|
  configuration.build_settings['TEST_TARGET_NAME'] = host.name
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(host)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.set_launch_target(host)
scheme.test_action.build_configuration = 'Debug'
scheme.save_as(project.path, 'IconAlertWatcher', true)
puts project.path
