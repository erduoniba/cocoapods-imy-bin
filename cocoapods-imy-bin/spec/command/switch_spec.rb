require File.expand_path('../../spec_helper', __FILE__)
require 'tmpdir'
require 'cocoapods-imy-bin/pod_modes'

module Pod
  describe Command::Bin::Switch do
    it 'saves a local mode without installing when requested' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'Podfile'), "plugin 'cocoapods-imy-bin'\ntarget 'Demo' do\n  pod 'Foo', '1.0'\nend\n")
        podfile = Podfile.from_file(File.join(root, 'Podfile'))
        podfile.defined_in_file = Pathname(root) + 'Podfile'
        Config.instance.stubs(:installation_root).returns(Pathname(root))
        Config.instance.stubs(:podfile).returns(podfile)

        command = Command::Bin::Switch.new(CLAide::ARGV.new(%w[Foo binary --no-install]))
        command.validate!
        command.run

        CBin::PodModes.read(root).should == { 'Foo' => 'binary' }
        podfile.binary_mode_overrides.should == { 'Foo' => 'binary' }
      end
    end

    it 'does not allow binary mode for a local path dependency' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'Podfile'), "plugin 'cocoapods-imy-bin'\ntarget 'Demo' do\n  pod 'Foo', :path => '../Foo'\nend\n")
        Config.instance.stubs(:installation_root).returns(Pathname(root))
        Config.instance.stubs(:podfile).returns(Podfile.from_file(File.join(root, 'Podfile')))

        command = Command::Bin::Switch.new(CLAide::ARGV.new(%w[Foo binary --no-install]))
        -> { command.validate! }.should.raise Informative
        File.exist?(CBin::PodModes.path(root)).should == false
      end
    end

    it 'keeps the selected mode if the subsequent installation fails' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'Podfile'), "plugin 'cocoapods-imy-bin'\ntarget 'Demo' do\n  pod 'Foo', '1.0'\nend\n")
        Config.instance.stubs(:installation_root).returns(Pathname(root))
        Config.instance.stubs(:podfile).returns(Podfile.from_file(File.join(root, 'Podfile')))
        install = mock('install')
        install.expects(:validate!)
        install.expects(:run).raises(Informative, 'install failed')
        Command::Bin::Install.stubs(:new).returns(install)

        command = Command::Bin::Switch.new(CLAide::ARGV.new(%w[Foo binary]))
        command.validate!
        -> { command.run }.should.raise Informative
        CBin::PodModes.read(root).should == { 'Foo' => 'binary' }
      end
    end

    it 'supports switching imy_pod between local, source and binary modes and reporting status' do
      Dir.mktmpdir do |root|
        podfile_path = File.join(root, 'Podfile')
        File.write(podfile_path, <<~RUBY)
          plugin 'cocoapods-imy-bin'
          use_binaries!
          target 'Demo' do
            imy_pod 'Foo', '1.0.0', :path => '../Foo'
            imy_pod 'Bar', '2.0.0', :path => '../Bar'
          end
        RUBY
        Config.instance.stubs(:installation_root).returns(Pathname(root))
        Config.instance.stubs(:podfile).returns(Podfile.from_file(podfile_path))

        # Switch Foo to local mode
        cmd = Command::Bin::Switch.new(CLAide::ARGV.new(%w[Foo local --no-install]))
        cmd.validate!
        cmd.run
        CBin::PodModes.read(root).should == { 'Foo' => 'local' }

        # Reload Podfile to verify imy_pod expands Foo as :path and Bar as versioned
        reloaded = Podfile.from_file(podfile_path)
        Config.instance.stubs(:podfile).returns(reloaded)
        reloaded.local_path_dependency?('Foo').should == true
        reloaded.local_path_dependency?('Bar').should == false

        # Check status payload
        status_cmd = Command::Bin::Status.new(CLAide::ARGV.new(%w[--json]))
        status_cmd.validate!
        payload = status_cmd.status_payload
        payload['default_mode'].should == 'binary'
        foo_status = payload['components'].find { |c| c['name'] == 'Foo' }
        bar_status = payload['components'].find { |c| c['name'] == 'Bar' }
        foo_status['mode'].should == 'local'
        foo_status['declared_version'].should == '1.0.0'
        foo_status['local_path'].should == '../Foo'
        bar_status['mode'].should == 'binary'

        # Switch all to source
        all_cmd = Command::Bin::Switch.new(CLAide::ARGV.new(%w[--all source --no-install]))
        all_cmd.validate!
        all_cmd.run
        CBin::PodModes.read(root).should == { 'Bar' => 'source', 'Foo' => 'source' }

        # Reset overrides
        reset_cmd = Command::Bin::Switch.new(CLAide::ARGV.new(%w[--reset --no-install]))
        reset_cmd.validate!
        reset_cmd.run
        CBin::PodModes.read(root).should == {}
      end
    end

    it 'loads dependencies from .imy-bin-config.json via imy_bin_config_dependencies without modifying Podfile' do
      Dir.mktmpdir do |root|
        podfile_path = File.join(root, 'Podfile')
        File.write(podfile_path, <<~RUBY)
          plugin 'cocoapods-imy-bin'
          use_binaries!
          target 'Demo' do
            imy_bin_config_dependencies
          end
        RUBY
        CBin::ComponentConfig.write(root, {
          'version' => 1,
          'project' => 'Demo',
          'environment' => 'dev',
          'defaultMode' => 'binary',
          'components' => [
            { 'name' => 'HDDynamicPod', 'version' => '0.1.2', 'mode' => 'binary', 'path' => '../HDDynamicPod', 'enabled' => true },
            { 'name' => 'HDStaticPod', 'version' => '0.1.11', 'mode' => 'local', 'path' => '../HDStaticPod', 'enabled' => true }
          ]
        })
        Config.instance.stubs(:installation_root).returns(Pathname(root))
        podfile = Podfile.from_file(podfile_path)
        Config.instance.stubs(:podfile).returns(podfile)

        podfile.local_path_dependency?('HDStaticPod').should == true
        podfile.local_path_dependency?('HDDynamicPod').should == false
        podfile.effective_mode_for_pod('HDStaticPod').should == 'local'
        podfile.effective_mode_for_pod('HDDynamicPod').should == 'binary'

        status_cmd = Command::Bin::Status.new(CLAide::ARGV.new(%w[--json]))
        status_cmd.validate!
        payload = status_cmd.status_payload
        dyn = payload['components'].find { |c| c['name'] == 'HDDynamicPod' }
        stat = payload['components'].find { |c| c['name'] == 'HDStaticPod' }
        dyn['declared_version'].should == '0.1.2'
        dyn['mode'].should == 'binary'
        stat['declared_version'].should == '0.1.11'
        stat['mode'].should == 'local'
      end

      it 'supports branch mode and target filtering via imy_bin_config_dependencies' do
        root = Dir.mktmpdir
        podfile_path = File.join(root, 'Podfile')
        File.write(podfile_path, <<~RUBY)
          plugin 'cocoapods-imy-bin'
          use_binaries!
          target 'AppMain' do
            imy_bin_config_dependencies 'AppMain'
          end
          target 'AppClip' do
            imy_bin_config_dependencies 'AppClip'
          end
        RUBY
        CBin::ComponentConfig.write(root, {
          'version' => 1,
          'project' => 'Demo',
          'environment' => 'dev',
          'defaultMode' => 'binary',
          'components' => [
            { 'name' => 'HDDynamicPod', 'mode' => 'branch', 'git' => 'https://example.com/dyn.git', 'branch' => 'feat/test', 'enabled' => true, 'targets' => ['AppMain'] },
            { 'name' => 'HDStaticPod', 'version' => '0.1.11', 'mode' => 'binary', 'enabled' => true, 'targets' => ['AppClip'] }
          ]
        })
        Config.instance.stubs(:installation_root).returns(Pathname(root))
        podfile = Podfile.from_file(podfile_path)
        Config.instance.stubs(:podfile).returns(podfile)

        app_main_target = podfile.target_definitions['AppMain']
        app_clip_target = podfile.target_definitions['AppClip']

        app_main_target.dependencies.map(&:name).should == ['HDDynamicPod']
        app_clip_target.dependencies.map(&:name).should == ['HDStaticPod']

        dyn_dep = app_main_target.dependencies.first
        dyn_dep.external_source[:git].should == 'https://example.com/dyn.git'
        dyn_dep.external_source[:branch].should == 'feat/test'
      end
    end
  end
end
