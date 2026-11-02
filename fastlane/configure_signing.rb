require 'xcodeproj'
project = Xcodeproj::Project.open('ios/Runner.xcodeproj')
profiles = { 'Runner' => ENV.fetch('APP_PROFILE_UUID'), 'ParkingWidget' => ENV.fetch('WIDGET_PROFILE_UUID') }
project.targets.each do |target|
  next unless profiles.key?(target.name)
  target.build_configurations.each do |config|
    config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
    config.build_settings['DEVELOPMENT_TEAM'] = ENV.fetch('APPLE_TEAM_ID')
    config.build_settings['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    config.build_settings['PROVISIONING_PROFILE_SPECIFIER'] = profiles.fetch(target.name)
  end
end
project.save
