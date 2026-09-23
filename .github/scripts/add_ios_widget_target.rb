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

# Explicitly ensure product reference name and path are set
widget_target.product_reference.name = "#{widget_name}.appex"
widget_target.product_reference.path = "#{widget_name}.appex"

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
version_name = '1.0.0'
version_number = '1'

if File.exist?('pubspec.yaml')
  pubspec_content = File.read('pubspec.yaml')
  if pubspec_content =~ /^version:\s*([0-9\.]+)\+([0-9]+)/
    version_name = $1
    version_number = $2
  end
end

puts "Setting Widget Target version: #{version_name} (Build: #{version_number})"

widget_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = widget_name
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = widget_bundle_id
  config.build_settings['INFOPLIST_FILE'] = "#{widget_name}/Info.plist"
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = version_number
  config.build_settings['MARKETING_VERSION'] = version_name
  config.build_settings['PRODUCT_BUNDLE_PACKAGE_TYPE'] = 'XPC!'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['SDKROOT'] = 'iphoneos'
  config.build_settings['SUPPORTED_PLATFORMS'] = 'iphoneos'
  config.build_settings['DEVELOPMENT_TEAM'] = ''
  config.build_settings['CODE_SIGN_STYLE'] = 'Manual'
  config.build_settings['CODE_SIGNING_REQUIRED'] = 'NO'
  config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  config.build_settings['CODE_SIGN_IDENTITY'] = ''
  config.build_settings['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = ''
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  config.build_settings['SWIFT_OPTIMIZATION_LEVEL'] = config.name == 'Release' ? '-O' : '-Onone'
  config.build_settings['ENABLE_BITCODE'] = 'NO'
  config.build_settings['SKIP_INSTALL'] = 'YES'
  config.build_settings['WRAPPER_EXTENSION'] = 'appex'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = [
    '$(inherited)',
    '@executable_path/Frameworks',
    '@executable_path/../../Frameworks'
  ]
end

# 5. Embed App Extension in Main Runner Target (must be BEFORE 'Thin Binary' to avoid Xcode build cycle)
embed_extensions_phase = main_target.copy_files_build_phases.find do |phase|
  phase.name == 'Embed Foundation Extensions' || phase.dst_subfolder_spec.to_s == '13'
end

unless embed_extensions_phase
  embed_extensions_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_extensions_phase.name = 'Embed Foundation Extensions'
  embed_extensions_phase.dst_subfolder_spec = '13' # PlugIns folder (String in latest xcodeproj)
  
  # Insert before 'Thin Binary' phase
  thin_binary_index = main_target.build_phases.index { |p| p.is_a?(Xcodeproj::Project::Object::PBXShellScriptBuildPhase) && p.name == 'Thin Binary' }
  if thin_binary_index
    main_target.build_phases.insert(thin_binary_index, embed_extensions_phase)
  else
    main_target.build_phases << embed_extensions_phase
  end
end

product_ref = widget_target.product_reference
build_file = embed_extensions_phase.add_file_reference(product_ref)
build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

# 6. Add dependency from Runner to Widget
main_target.add_dependency(widget_target)

# 7. Add Widget Target to Runner Scheme Build Actions
scheme_path = "#{project_path}/xcshareddata/xcschemes/Runner.xcscheme"
if File.exist?(scheme_path)
  begin
    scheme = Xcodeproj::XCScheme.new(scheme_path)
    has_entry = scheme.build_action.entries.any? do |entry|
      entry.buildable_references.any? { |r| r.blueprint_name == widget_name }
    end
    
    unless has_entry
      entry = Xcodeproj::XCScheme::BuildAction::Entry.new(widget_target)
      scheme.build_action.add_entry(entry)
      scheme.save_as(project_path, 'Runner', true)
      puts "Successfully added #{widget_name} to Runner.xcscheme build actions!"
    end
  rescue => e
    puts "Warning: Could not update Runner.xcscheme: #{e.message}"
  end
end

# Save project
project.save
puts "Successfully configured #{widget_name} target in #{project_path}!"
