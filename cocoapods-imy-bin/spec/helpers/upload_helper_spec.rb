require File.expand_path('../../spec_helper', __FILE__)
require 'cocoapods-imy-bin/helpers/upload_helper'

module CBin
  describe Upload::Helper do
    it 'keeps the preferred environment token out of process arguments' do
      spec = Struct.new(:name, :version).new('Pod A', '1.2.3')
      helper = Upload::Helper.new(spec, [], [])
      config = Struct.new(:binary_upload_url, :binary_upload_token).new('https://binary.example/frameworks', 'config-token')
      previous_token = ENV['BINARY_SERVER_TOKEN']
      ENV['BINARY_SERVER_TOKEN'] = 'environment-token'
      CBin.stubs(:config).returns(config)

      arguments = helper.curl_arguments('/tmp/Pod A.zip')

      arguments.should.include '--form'
      arguments.should.include 'name=Pod A'
      arguments.should.include 'file=@/tmp/Pod A.zip'
      arguments.should.include '--config'
      arguments.join(' ').should.not.include 'environment-token'
      helper.curl_config.should.include 'Authorization: Bearer environment-token'
      arguments.last.should == 'https://binary.example/frameworks'
    ensure
      ENV['BINARY_SERVER_TOKEN'] = previous_token
    end

    it 'rejects an unencrypted remote server before uploading' do
      spec = Struct.new(:name, :version).new('Foo', '1.0.0')
      helper = Upload::Helper.new(spec, false, [])
      config = Struct.new(:binary_download_url, :binary_upload_url, :binary_upload_token,
                          :binary_repo_url, :download_file_type).new(
        'http://binary.example/frameworks/%s/%s/zip', 'http://binary.example/frameworks',
        'test-token', 'git@example.com:specs.git', 'zip'
      )
      CBin.stubs(:config).returns(config)

      -> { helper.preflight! }.should.raise Pod::Informative
    end

    it 'uploads an archive without exposing the token in curl arguments' do
      spec = Struct.new(:name, :version).new('Foo', '1.0.0')
      helper = Upload::Helper.new(spec, false, [])
      config = Struct.new(:binary_upload_url, :binary_upload_token).new('https://binary.example/frameworks', 'secret')
      CBin.stubs(:config).returns(config)
      status = mock('curl status')
      status.stubs(:success?).returns(true)
      Open3.expects(:capture3).with do |*arguments|
        options = arguments.pop
        arguments.last == config.binary_upload_url &&
          !arguments.join(' ').include?('secret') &&
          options[:stdin_data].include?('Bearer secret')
      end.returns(['', '', status])

      helper.curl_zip('Foo.zip').should == true
    end

    it 'rolls back the uploaded artifact when pushing the spec fails' do
      require 'tmpdir'
      spec = Struct.new(:name, :version).new('Foo', '1.0.0')
      helper = Upload::Helper.new(spec, false, [])
      Dir.mktmpdir do |root|
        builder = mock('builder')
        builder.stubs(:root_dir).returns(root)
        CBin::Config::Builder.stubs(:instance).returns(builder)
        helper.stubs(:preflight!)
        helper.stubs(:archive_file).returns('Foo.zip')
        helper.stubs(:spec_creator).returns('Foo.binary.podspec.json')
        helper.stubs(:curl_zip).returns(true)
        helper.stubs(:push_binary_repo).raises(Pod::Informative, 'push failed')
        helper.expects(:rollback_artifact).returns(true)

        -> { helper.upload }.should.raise Pod::Informative
      end
    end

    it 'reports the spec push failure even when the rollback request raises' do
      require 'tmpdir'
      spec = Struct.new(:name, :version).new('Foo', '1.0.0')
      helper = Upload::Helper.new(spec, false, [])
      Dir.mktmpdir do |root|
        builder = mock('builder')
        builder.stubs(:root_dir).returns(root)
        CBin::Config::Builder.stubs(:instance).returns(builder)
        helper.stubs(:preflight!)
        helper.stubs(:archive_file).returns('Foo.zip')
        helper.stubs(:spec_creator).returns('Foo.binary.podspec.json')
        helper.stubs(:curl_zip).returns(true)
        helper.stubs(:push_binary_repo).raises(Pod::Informative, 'push failed')
        config = mock('binary config')
        config.stubs(:binary_upload_url).returns('https://binary.example/frameworks')
        config.stubs(:binary_upload_token).returns('test-token')
        CBin.stubs(:config).returns(config)
        Open3.stubs(:capture3).raises(Errno::ECONNRESET)

        error = -> { helper.upload }.should.raise Pod::Informative
        error.message.should.include 'push failed'
        error.message.should.include '回滚失败'
      end
    end
  end
end
