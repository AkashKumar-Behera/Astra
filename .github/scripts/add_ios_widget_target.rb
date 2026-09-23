require 'xcodeproj'

project_path = 'ios/Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

widget_name = 'FriendDistanceWidget'
widget_bundle_id = 'com.astra.always.FriendDistanceWidget'

# Check if target already exists
existing_target = project.targets.find { |t| t.name == widget_name }
if existing_target
  puts "Widget target '#{widget_name}' already exists in #{project_path}"
  exit 0
end

main_target = project.targets.find { |t| t.name == 'Runner' }
unless main_target
  puts "Error: Main target 'Runner' not found in #{project_path}"
  exit 1
end

# 1. Create native target for widget extension
widget_target = project.new_target(
  :app_extension,
  widget_name,
  :ios,
  '17.0',
  project.products_group,
  :swift
)

# 2. Add files to Widget Group
widget_group = project.main_group.find_subpath(widget_name, true)
widget_group.set_source_tree('<group>')
widget_group.set_path(widget_name)

swift_file_ref = widget_group.new_file('FriendDistanceWidget.swift')
info_plist_ref = widget_group.new_file('Info.plist')

# Add swift file to Sources build phase
widget_target.source_build_phase.add_file_reference(swift_file_ref)

# 3. Add Frameworks
widget_target.frameworks_build_phase.add_file_reference(
  project.frameworks_group.new_file('WidgetKit.framework')
)
widget_target.frameworks_build_phase.add_file_reference(
  project.frameworks_group.new_file('SwiftUI.framework')
)

# 4. Configure Build Settings
widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = widget_bundle_id
  config.build_settings['INFOPLIST_FILE'] = "#{widget_name}/Info.plist"
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['CODE_SIGN_IDENTITY'] = ''
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = config.name == 'Release' ? '-O' : '-Onone'
  config.build_settings['ENABLE_BITCODE'] = 'NO'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
end

# 5. Embed App Extension in Main Runner Target
embed_extensions_phase = main_target.copy_files_build_phases.find do |phase|
  phase.name == 'Embed Foundation Extensions' || phase.dst_subfolder_spec == 13
end

unless embed_extensions_phase
  embed_extensions_phase = main_target.new_copy_files_build_phase('Embed Foundation Extensions')
  embed_extensions_phase.dst_subfolder_spec = 13 # PlugIns folder
end

product_ref = widget_target.product_reference
build_file = embed_extensions_phase.add_file_reference(product_ref)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# 6. Add dependency from Runner to Widget
main_target.add_dependency(widget_target)

# Save project
project.save
puts "Successfully configured #{widget_name} target in #{project_path}!"
