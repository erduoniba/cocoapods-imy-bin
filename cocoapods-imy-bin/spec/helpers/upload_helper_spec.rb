require File.expand_path('../../spec_helper', __FILE__)
require 'cocoapods-imy-bin/helpers/upload_helper'

module CBin
  describe Upload::Helper do
    it 'uses argument-based curl invocation and prefers the environment token' do
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
      arguments.should.include 'Authorization: Bearer environment-token'
      arguments.last.should == 'https://binary.example/frameworks'
    ensure
      ENV['BINARY_SERVER_TOKEN'] = previous_token
    end
  end
end
