

# copy from https://github.com/CocoaPods/cocoapods-packager

require 'open3'
require 'cocoapods-imy-bin/native/podfile'
require 'cocoapods/command/gen'
require 'cocoapods/generate'
require 'cocoapods-imy-bin/helpers/framework_builder'
require 'cocoapods-imy-bin/helpers/library_builder'
require 'cocoapods-imy-bin/helpers/sources_helper'
require 'cocoapods-imy-bin/command/bin/spec/push'

module CBin
  class Upload
    class Helper
      include CBin::SourcesHelper

      def initialize(spec,code_dependencies,sources)
        @spec = spec
        @code_dependencies = code_dependencies
        @sources = sources
      end

      def upload
        puts "upload"
        Dir.chdir(CBin::Config::Builder.instance.root_dir) do
          # 创建binary-template.podsepc
          # 上传二进制文件
          # 上传二进制 podspec
          res_zip = curl_zip
          if res_zip
            filename = spec_creator
            push_binary_repo(filename)
          end
          res_zip
        end
      end

      def spec_creator
        spec_creator = CBin::SpecificationSource::Creator.new(@spec)
        spec_creator.create
        spec_creator.write_spec_file
        spec_creator.filename
      end

      #推送二进制
      # curl http://ci.xxx:9192/frameworks -F "name=IMYFoundation" -F "version=7.7.4.2" -F "annotate=IMYFoundation_7.7.4.2_log" -F "file=@bin-zip/bin_IMYFoundation_7.7.4.2.zip"
      def curl_zip
        zip_file = "#{CBin::Config::Builder.instance.library_file(@spec)}.zip"
        res = File.exist?(zip_file)
        puts "curl_zip #{zip_file} #{res}"
        unless res
          zip_file = CBin::Config::Builder.instance.framework_zip_file(@spec) + ".zip"
          res = File.exist?(zip_file)
        end
        if res
          command = curl_arguments(zip_file)
          puts "上传二进制文件到 #{CBin.config.binary_upload_url}"
          upload_result, upload_error, status = Open3.capture3(*command)
          puts upload_result unless upload_result.empty?
          UI.warn upload_error unless upload_error.empty?
          res = status.success?
        end

        res
      end

      def curl_arguments(zip_file)
        arguments = [
          'curl',
          '--fail',
          '--silent',
          '--show-error',
          '--request', 'POST',
          '--form', "name=#{@spec.name}",
          '--form', "version=#{@spec.version}",
          '--form', "annotate=#{@spec.name}_#{@spec.version}_log",
          '--form', "file=@#{zip_file}"
        ]
        token = ENV['BINARY_SERVER_TOKEN'].to_s
        token = CBin.config.binary_upload_token.to_s if token.empty?
        arguments += ['--header', "Authorization: Bearer #{token}"] unless token.empty?
        arguments << CBin.config.binary_upload_url
        arguments
      end


      # 上传二进制 podspec
      def push_binary_repo(binary_podsepc_json)
        argvs = [
            "#{binary_podsepc_json}",
            "--binary",
            "--sources=#{sources_option(@code_dependencies, @sources)},https:\/\/cdn.cocoapods.org",
            "--skip-import-validation",
            "--use-libraries",
            "--allow-warnings",
            "--verbose",
            "--code-dependencies"
        ]
        if @verbose
          argvs += ['--verbose']
        end

        push = Pod::Command::Bin::Repo::Push.new(CLAide::ARGV.new(argvs))
        push.validate!
        push.run
      end

    end
  end
end
