#!/usr/bin/env ruby
# Generate an isolated native test project when Flutter/CocoaPods cannot build.
# Requires the xcodeproj gem (also distributed with CocoaPods).
# Usage: ruby tools/ar_ios_test_project.rb /absolute/path/to/output-directory
# This tests actual reader sources, not Runner integration or bundled resources.
require 'fileutils'
require 'xcodeproj'

abort 'Usage: ruby tools/ar_ios_test_project.rb OUTPUT_DIRECTORY' unless ARGV.length == 1
root = File.expand_path('../ios', __dir__)
output = File.expand_path(ARGV.first)
project_path = File.join(output, 'ReaderNative.xcodeproj')
abort "Refusing to overwrite #{project_path}" if File.exist?(project_path)
FileUtils.mkdir_p(output)
project = Xcodeproj::Project.new(project_path)
framework = project.new_target(:framework, 'Runner', :ios, '15.0')
tests = project.new_target(:unit_test_bundle, 'ReaderNativeTests', :ios, '15.0')
tests.add_dependency(framework)
tests.frameworks_build_phase.add_file_reference(framework.product_reference)
[
  'Runner/ScanAnyPage/ScanGeometry.swift',
  'Runner/CharacterReader/CharacterReaderPresentation.swift',
  'Runner/CharacterReader/CharacterReaderViewController.swift',
].each do |path|
  framework.source_build_phase.add_file_reference(project.main_group.new_file(File.join(root, path)))
end
framework.resources_build_phase.add_file_reference(project.main_group.new_file(
  File.join(root, 'Runner/CharacterReader/little_buddy.usdz')
))
tests.source_build_phase.add_file_reference(project.main_group.new_file(
  File.join(root, 'RunnerTests/CharacterReaderPresentationTests.swift')
))
[framework, tests].each do |target|
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['ENABLE_TESTABILITY'] = 'YES'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "com.motnhi.nativevalidation.#{target.name}"
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
  end
end
project.save
scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(framework)
scheme.add_build_target(tests)
scheme.add_test_target(tests)
scheme.save_as(project.path, 'ReaderNative')
puts project_path
