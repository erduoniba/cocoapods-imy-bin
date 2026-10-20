require File.expand_path('../spec_helper', __FILE__)
require 'tmpdir'
require 'json'
require 'cocoapods-imy-bin/managed_policy'
require 'cocoapods-imy-bin/native/podfile'

module Pod
  describe 'managed project policies' do
    revision = 'd31d30d7-bfe3-4bc0-b101-a7855327def1'
    payload = {
      'project' => 'SampleApp', 'revision' => revision,
      'targets' => [{ 'name' => 'App', 'dependencies' => [
        { 'name' => 'HDDynamicPod', 'version' => '1.0.0', 'mode' => 'binary' },
        { 'name' => 'HDStaticPod', 'version' => '2.0.0', 'mode' => 'source' }
      ] }]
    }

    it 'loads a pinned policy and applies versions and modes in a Podfile' do
      Dir.mktmpdir do |root|
        File.write(CBin::ManagedPolicy.path(root), JSON.generate(payload))
        File.write(File.join(root, 'Podfile'), <<~PODFILE)
          plugin 'cocoapods-imy-bin'
          target 'App' do
            imy_bin_dependencies 'App', project: 'SampleApp'
          end
        PODFILE
        podfile = Podfile.from_file(File.join(root, 'Podfile'))
        podfile.dependencies.map(&:name).sort.should == %w[HDDynamicPod HDStaticPod]
        podfile.managed_policy_modes.should == { 'HDDynamicPod' => 'binary', 'HDStaticPod' => 'source' }
        dynamic = Struct.new(:name, :root, :spec).new('HDDynamicPod', Struct.new(:name).new('HDDynamicPod'), nil)
        podfile.use_binary_for_spec?(dynamic).should == true

        CBin::PodModes.write(root, 'HDDynamicPod' => 'source')
        podfile.use_binary_for_spec?(dynamic).should == false
        previous = ENV['CI']
        begin
          ENV['CI'] = 'true'
          ENV['IMY_BIN_POLICY_REVISION'] = revision
          podfile.use_binary_for_spec?(dynamic).should == true
        ensure
          ENV['CI'] = previous
          ENV.delete('IMY_BIN_POLICY_REVISION')
        end
      end
    end

    it 'rejects conflicting modes across targets and a mismatched fixed revision' do
      conflict = Marshal.load(Marshal.dump(payload))
      conflict['targets'] << { 'name' => 'Other', 'dependencies' => [
        { 'name' => 'HDDynamicPod', 'version' => '1.0.0', 'mode' => 'source' }
      ] }
      -> { CBin::ManagedPolicy.validate!(conflict, project: 'SampleApp') }.should.raise Informative
      Dir.mktmpdir do |root|
        File.write(CBin::ManagedPolicy.path(root), JSON.generate(payload))
        -> { CBin::ManagedPolicy.read(root, project: 'SampleApp', revision: '0' * 8) }.should.raise Informative
      end
    end

    it 'keeps the cache unchanged when a network response is invalid' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'Podfile'), "plugin 'cocoapods-imy-bin'\n")
        File.write(CBin::ManagedPolicy.path(root), JSON.generate(payload))
        response = Net::HTTPOK.new('1.1', '200', 'OK')
        response.body = JSON.generate(payload.merge('project' => 'Other'))
        response.instance_variable_set(:@read, true)
        client = mock('http client')
        client.expects(:request).returns(response)
        Net::HTTP.expects(:start).yields(client).returns(response)
        -> { CBin::ManagedPolicy.sync(root, project: 'SampleApp', revision: revision,
                                     server: 'http://127.0.0.1:8080', token: 'secret') }.should.raise Informative
        CBin::ManagedPolicy.read(root, project: 'SampleApp', revision: revision).should == payload
      end
    end

    it 'requires an exact revision in CI and does not fall back after a connection failure' do
      Dir.mktmpdir do |root|
        File.write(File.join(root, 'Podfile'), "plugin 'cocoapods-imy-bin'\n")
        File.write(CBin::ManagedPolicy.path(root), JSON.generate(payload))
        old_ci, old_revision = ENV['CI'], ENV['IMY_BIN_POLICY_REVISION']
        begin
          ENV['CI'] = 'true'
          ENV.delete('IMY_BIN_POLICY_REVISION')
          -> { CBin::ManagedPolicy.read(root, project: 'SampleApp') }.should.raise Informative
          Net::HTTP.expects(:start).raises(SocketError, 'offline')
          -> { CBin::ManagedPolicy.sync(root, project: 'SampleApp', revision: revision,
                                       server: 'http://127.0.0.1:8080', token: 'secret') }.should.raise Informative
        ensure
          ENV['CI'], ENV['IMY_BIN_POLICY_REVISION'] = old_ci, old_revision
        end
      end
    end
  end
end

module Pod
  describe 'managed policy lockfile verification' do
    it 'requires the exact mode repo and version after install' do
      Dir.mktmpdir do |root|
        policy = {
          'project' => 'SampleApp', 'revision' => 'd31d30d7-bfe3-4bc0-b101-a7855327def1',
          'targets' => [{ 'name' => 'App', 'dependencies' => [
            { 'name' => 'Foo', 'version' => '1.0.0', 'mode' => 'binary' }
          ] }]
        }
        File.write(CBin::ManagedPolicy.path(root), JSON.generate(policy))
        lockfile = <<~LOCK
          PODS:
            - Foo (1.0.0)
          DEPENDENCIES:
            - Foo (= 1.0.0)
          SPEC REPOS:
            binary-repo:
              - Foo
        LOCK
        File.write(File.join(root, 'Podfile.lock'), lockfile)
        CBin::ManagedPolicy.verify_lockfile!(root, project: 'SampleApp',
          source_repo: 'source-repo', binary_repo: 'binary-repo').should == true
        File.write(File.join(root, 'Podfile.lock'), lockfile.sub('binary-repo', 'source-repo'))
        CBin::ManagedPolicy.verify_lockfile!(root, project: 'SampleApp',
          source_repo: 'source-repo', binary_repo: 'binary-repo',
          mode_overrides: { 'Foo' => 'source' }).should == true
        File.write(File.join(root, 'Podfile.lock'), lockfile)
        -> { CBin::ManagedPolicy.verify_lockfile!(root, project: 'SampleApp',
          source_repo: 'source-repo', binary_repo: 'other-repo') }.should.raise Informative
        File.write(File.join(root, 'Podfile.lock'), lockfile.sub('1.0.0', '2.0.0'))
        -> { CBin::ManagedPolicy.verify_lockfile!(root, project: 'SampleApp',
          source_repo: 'source-repo', binary_repo: 'binary-repo') }.should.raise Informative
      end
    end
  end
end
