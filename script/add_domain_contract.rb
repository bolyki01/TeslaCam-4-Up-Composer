#!/usr/bin/env ruby
# Adds TeslaCam/DomainContract.swift to the project and to every
# TeslaCam app target's Sources build phase. Idempotent: re-running is
# a no-op.

require 'xcodeproj'

project_path = File.join(__dir__, '..', 'TeslaCam.xcodeproj')
project = Xcodeproj::Project.open(project_path)

teslacam_group = project.main_group.find_subpath('TeslaCam', false)
abort('Cannot find TeslaCam group') unless teslacam_group

file_name = 'DomainContract.swift'
file_ref = teslacam_group.files.find { |f| f.path == file_name }
unless file_ref
  file_ref = teslacam_group.new_file(file_name)
  puts "Added file reference: #{file_name}"
end

project.targets.each do |target|
  next unless target.product_type == 'com.apple.product-type.application'
  next unless target.name.start_with?('TeslaCam')
  build_phase = target.source_build_phase
  already = build_phase.files.any? { |bf| bf.file_ref == file_ref }
  unless already
    build_phase.add_file_reference(file_ref)
    puts "Added to target: #{target.name}"
  end
end

project.save
puts 'Done.'
