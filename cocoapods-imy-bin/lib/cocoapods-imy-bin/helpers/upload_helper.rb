

# copy from https://github.com/CocoaPods/cocoapods-packager

require 'open3'
require 'uri'
require 'digest'
require 'fileutils'
require 'cocoapods-imy-bin/native/podfile'
require 'cocoapods/command/gen'
require 'cocoapods/generate'
require 'cocoapods-imy-bin/helpers/framework_builder'
require 'cocoapods-imy-bin/helpers/library_builder'
require 'cocoapods-imy-bin/helpers/xcframework_builder'
require 'cocoapods-imy-bin/helpers/xcframework_spec'
require 'cocoapods-imy-bin/helpers/sources_helper'
require 'cocoapods-imy-bin/command/bin/spec/push'
require 'cocoapods-imy-bin/pod_modes'

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
        preflight!
        Dir.chdir(CBin::Config::Builder.instance.root_dir) do
          zip_file = archive_file
          raise Pod::Informative, "未找到 #{@spec.name} #{@spec.version} 的归档 ZIP；未上传制品." unless zip_file

          filename = spec_creator
          raise Pod::Informative, "上传 #{@spec.name} #{@spec.version} 失败；未推送 podspec." unless curl_zip(zip_file)

          begin
            raise Pod::Informative, '二进制 podspec 推送返回失败.' if push_binary_repo(filename) == false
          rescue Exception => error
            if rollback_artifact
              raise Pod::Informative, "二进制 podspec 推送失败，已回滚刚上传的制品: #{error.message}"
            end
            raise Pod::Informative, "二进制 podspec 推送失败且制品回滚失败，请检查 #{@spec.name} #{@spec.version}: #{error.message}"
          end
          true
        end
      end

      def preflight!
        unless CBin::PodModes::NAME_PATTERN.match?(@spec.name.to_s) && CBin::PodModes::NAME_PATTERN.match?(@spec.version.to_s)
          raise Pod::Informative, '组件名或版本不符合私有服务的标识格式.'
        end
        download_url = format(CBin.config.binary_download_url.to_s, @spec.name, @spec.version)
        validate_url!(download_url)
        upload_url = CBin.config.binary_upload_url
        uri = validate_url!(upload_url)
        raise Pod::Informative, '上传地址必须以 /frameworks 结尾.' unless uri.path.end_with?('/frameworks')
        unless CBin.config.download_file_type == 'zip'
          raise Pod::Informative, '私有二进制服务只接受 ZIP；请将 download_file_type 设为 zip.'
        end
        unless %w[localhost 127.0.0.1 ::1].include?(uri.host) || !token.empty?
          raise Pod::Informative, '远程二进制服务需要 BINARY_SERVER_TOKEN 环境变量.'
        end
        if uri.scheme != 'https' && !%w[localhost 127.0.0.1 ::1].include?(uri.host)
          raise Pod::Informative, '远程二进制服务必须使用 HTTPS，以免泄漏上传令牌.'
        end
        raise Pod::Informative, '请配置 binary_repo_url.' if CBin.config.binary_repo_url.to_s.empty?
      rescue ArgumentError, URI::InvalidURIError => error
        raise Pod::Informative, "二进制服务地址无效: #{error.message}"
      end

      def validate_url!(url)
        uri = URI.parse(url)
        unless uri.is_a?(URI::HTTP) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
          raise Pod::Informative, "无效的二进制服务地址: #{url}"
        end
        uri
      end

      def token
        value = ENV['BINARY_SERVER_TOKEN'].to_s
        value = CBin.config.binary_upload_token.to_s if value.empty?
        raise Pod::Informative, '上传令牌不能包含换行或控制字符.' if value.match?(/[\x00-\x1f\x7f]/)
        value
      end

      def spec_creator
        return xcframework_spec_file if xcframework_zip?

        spec_creator = CBin::SpecificationSource::Creator.new(@spec)
        spec_creator.create
        spec_creator.write_spec_file
        spec_creator.filename
      end

      def xcframework_zip?
        File.basename(archive_file.to_s) == CBin::XCFrameworkBuilder.zip_name(@spec)
      end

      # 二进制 spec 带 sha256：CocoaPods 下载后校验 ZIP，重新发布时也会让缓存失效。
      def xcframework_spec_file
        download_url = format(CBin.config.binary_download_url.to_s, @spec.name, @spec.version)
        sha256 = Digest::SHA256.file(archive_file).hexdigest
        spec = CBin::XCFrameworkSpec.create(@spec, download_url: download_url, sha256: sha256)
        dir = CBin::Config::Builder.instance.binary_json_dir_name
        FileUtils.mkdir_p(dir)
        filename = File.join(dir, "#{@spec.name}.binary.podspec.json")
        File.write(filename, spec.to_pretty_json)
        filename
      end

      #推送二进制
      # curl http://ci.xxx:9192/frameworks -F "name=IMYFoundation" -F "version=7.7.4.2" -F "annotate=IMYFoundation_7.7.4.2_log" -F "file=@bin-zip/bin_IMYFoundation_7.7.4.2.zip"
      def archive_file
        [File.join(CBin::Config::Builder.instance.zip_dir_name, CBin::XCFrameworkBuilder.zip_name(@spec)),
         "#{CBin::Config::Builder.instance.library_file(@spec)}.zip",
         "#{CBin::Config::Builder.instance.framework_zip_file(@spec)}.zip"].find { |filename| File.file?(filename) }
      end

      def curl_zip(zip_file = archive_file)
        return false unless zip_file

        Pod::UI.puts "上传二进制文件到 #{CBin.config.binary_upload_url}"
        output, error, status = Open3.capture3(*curl_arguments(zip_file), stdin_data: curl_config)
        Pod::UI.puts output unless output.empty?
        Pod::UI.warn error unless error.empty?
        status.success?
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
        arguments += ['--config', '-'] unless token.empty?
        arguments << CBin.config.binary_upload_url
        arguments
      end

      def curl_config
        return '' if token.empty?

        escaped_token = token.gsub(/[\\"]/) { |character| "\\#{character}" }
        "header = \"Authorization: Bearer #{escaped_token}\"\n"
      end

      def rollback_artifact
        url = "#{CBin.config.binary_upload_url.chomp('/')}/#{@spec.name}/#{@spec.version}"
        arguments = ['curl', '--fail', '--silent', '--show-error', '--request', 'DELETE']
        arguments += ['--config', '-'] unless token.empty?
        arguments << url
        _output, error, status = Open3.capture3(*arguments, stdin_data: curl_config)
        Pod::UI.warn error unless error.empty?
        status.success?
      rescue StandardError => error
        Pod::UI.warn "制品回滚请求失败: #{error.message}"
        false
      end


      # 上传二进制 podspec
      def push_binary_repo(binary_podsepc_json)
        sources = sources_option(@code_dependencies, @sources)
        unless CBin.config.binary_repo_url.to_s.start_with?('file://')
          sources = [sources, 'https://cdn.cocoapods.org'].reject(&:empty?).join(',')
        end
        argvs = [
          binary_podsepc_json.to_s,
          '--binary',
          "--sources=#{sources}",
          '--skip-import-validation',
          '--skip-tests',
          '--allow-warnings',
          '--verbose',
          '--code-dependencies'
        ]
        argvs << '--use-libraries' unless xcframework_zip? || @spec.to_hash['static_framework'] == false
        argvs << '--verbose' if @verbose

        push = Pod::Command::Bin::Repo::Push.new(CLAide::ARGV.new(argvs))
        push.validate!
        push.run
      end

    end
  end
end
