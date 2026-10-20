require File.expand_path('../../spec_helper', __FILE__)
require 'tmpdir'
require 'cocoapods-imy-bin/helpers/xcframework_builder'
require 'cocoapods-imy-bin/helpers/xcframework_spec'

module CBin
  describe XCFrameworkSpec do
    def code_spec(&block)
      Pod::Specification.new do |s|
        s.name = 'HDStaticPod'
        s.version = '0.1.11'
        s.summary = 'Demo'
        s.homepage = 'https://example.com'
        s.license = { type: 'MIT', file: 'LICENSE' }
        s.authors = { 'demo' => 'demo@example.com' }
        s.source = { git: 'file:///tmp/HDStaticPod', tag: s.version.to_s }
        s.ios.deployment_target = '15.0'
        s.swift_version = '5.0'
        s.static_framework = true
        s.source_files = 'HDStaticPod/Classes/**/*.{h,m,swift}'
        s.dependency 'Alamofire', '~> 5.0'
        block&.call(s)
      end
    end

    it 'points the binary spec at the verified XCFramework ZIP' do
      spec = XCFrameworkSpec.create(code_spec, download_url: 'http://127.0.0.1:8080/frameworks/HDStaticPod/0.1.11/zip',
                                               sha256: 'a' * 64)
      hash = spec.to_hash

      hash['source'].should == { 'http' => 'http://127.0.0.1:8080/frameworks/HDStaticPod/0.1.11/zip',
                                 'type' => 'zip', 'sha256' => 'a' * 64 }
      hash['vendored_frameworks'].should == 'HDStaticPod.xcframework'
      hash.key?('source_files').should == false
      hash['dependencies'].should == { 'Alamofire' => ['~> 5.0'] }
      hash['static_framework'].should == true
      hash['platforms'].should == { 'ios' => '15.0' }
      spec.version.to_s.should == '0.1.11'
    end

    it 'keeps subspecs resolvable but strips their sources' do
      spec = XCFrameworkSpec.create(code_spec { |s|
        s.subspec('Core') { |core| core.source_files = 'Core/**/*.swift' }
        s.test_spec('Tests') { |test| test.source_files = 'Tests/**/*.swift' }
      }, download_url: 'http://127.0.0.1/zip')

      core = spec.subspecs.first
      core.name.should == 'HDStaticPod/Core'
      core.to_hash.key?('source_files').should == false
      spec.to_hash.key?('testspecs').should == false
    end

    it 'ships resource bundles beside the framework' do
      spec = XCFrameworkSpec.create(code_spec { |s|
        s.resource_bundles = { 'HDStaticPodAssets' => ['Assets/*.png'] }
      }, download_url: 'http://127.0.0.1/zip')

      spec.to_hash['resources'].should == ['HDStaticPodAssets.bundle']
      spec.to_hash.key?('resource_bundles').should == false
    end

    it 'refuses specs whose binaries or loose resources cannot be repackaged' do
      error = -> {
        XCFrameworkSpec.create(code_spec { |s| s.ios.vendored_frameworks = 'Vendor/Foo.framework' },
                               download_url: 'http://127.0.0.1/zip')
      }.should.raise Pod::Informative
      error.message.should.include 'ios.vendored_frameworks'

      -> {
        XCFrameworkSpec.create(code_spec { |s| s.resources = 'Assets/*.png' }, download_url: 'http://127.0.0.1/zip')
      }.should.raise Pod::Informative
    end
  end

  describe XCFrameworkBuilder do
    it 'builds both SDKs for distribution and merges them into one ZIP' do
      Dir.mktmpdir do |dir|
        work = Pathname.new(dir)
        (work + 'Pods.xcodeproj').mkpath
        spec = Pod::Specification.new do |s|
          s.name = 'HDDynamicPod'
          s.version = '0.1.0'
          s.ios.deployment_target = '15.0'
        end
        commands = []
        runner = lambda do |arguments, _label|
          commands << arguments
          if arguments[1] == 'build'
            sdk = arguments[arguments.index('-sdk') + 1]
            FileUtils.mkdir_p(work + 'xcframework-build' + sdk + 'HDDynamicPod.framework')
          end
          ''
        end

        zip = XCFrameworkBuilder.new(spec, work_dir: work, output_dir: work + 'out', runner: runner).build

        zip.basename.to_s.should == 'HDDynamicPod.xcframework_0.1.0.zip'
        builds = commands.select { |command| command[1] == 'build' }
        builds.map { |command| command[command.index('-sdk') + 1] }.should == %w[iphoneos iphonesimulator]
        builds.each do |command|
          command.should.include 'BUILD_LIBRARY_FOR_DISTRIBUTION=YES'
          command.should.include 'ONLY_ACTIVE_ARCH=NO'
          command[command.index('-target') + 1].should == 'HDDynamicPod'
        end
        create = commands.find { |command| command[1] == '-create-xcframework' }
        create.count('-framework').should == 2
        create.last.should.end_with 'HDDynamicPod.xcframework'
        commands.last.first.should == 'zip'
      end
    end

    it 'fails clearly when a slice produced no framework' do
      Dir.mktmpdir do |dir|
        work = Pathname.new(dir)
        (work + 'Pods.xcodeproj').mkpath
        spec = Pod::Specification.new { |s| s.name = 'Foo'; s.version = '1.0.0' }
        builder = XCFrameworkBuilder.new(spec, work_dir: work, output_dir: work, runner: ->(*) { '' })

        error = -> { builder.build }.should.raise Pod::Informative
        error.message.should.include 'iphoneos'
      end
    end
  end
end
