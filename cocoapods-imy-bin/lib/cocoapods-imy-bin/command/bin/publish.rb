require 'fileutils'
require 'json'
require 'open3'
require 'cocoapods-imy-bin/command/bin/archive'
require 'cocoapods-imy-bin/command/bin/spec/push'
require 'cocoapods-imy-bin/helpers/upload_helper'

module Pod
  class Command
    class Bin < Command
      class Publish < Bin
        self.summary = '构建并发布单个组件到私有二进制服务和 spec 仓库.'
        self.arguments = [CLAide::Argument.new('NAME.podspec', false)]

        def self.options
          [
            ['--env=ENV', '配置环境：dev、debug_iphoneos 或 release_iphoneos'],
            ['--configuration=CONFIG', 'Xcode 构建配置，默认 Release'],
            ['--code-dependencies', '构建时使用源码依赖'],
            ['--sources=URLS', '额外 spec 源，逗号分隔'],
            ['--no-clean', '保留构建工程以供排查'],
            ['--dry-run', '只执行预检与本地归档构建，不打 Tag、不上传制品或推送 spec'],
            ['--skip-tag', '跳过创建组件 Git Tag'],
            ['--skip-code-spec', '跳过推送源码 podspec 到源码 spec 仓库'],
            ['--allow-prerelease', '允许发布 pre-release 版本（例如 beta）'],
            ['--auto-commit', '发布前自动暂存并提交本地代码变更'],
            ['--push', '发布时自动推送代码提交与 Git Tag 到远程仓库']
          ].concat(super)
        end

        def initialize(argv)
          @podspec = argv.shift_argument || code_spec_files.first
          @env = argv.option('env', 'dev')
          @configuration = argv.option('configuration', 'Release')
          @code_dependencies = argv.flag?('code-dependencies')
          @sources = argv.option('sources')
          @clean = argv.flag?('clean', true)
          @dry_run = argv.flag?('dry-run', false)
          @skip_tag = argv.flag?('skip-tag', false)
          @skip_code_spec = argv.flag?('skip-code-spec', false)
          @allow_prerelease = argv.flag?('allow-prerelease', false)
          @auto_commit = argv.flag?('auto-commit', false)
          @push = argv.flag?('push', false)
          @created_tag = false
          CBin.config.set_configuration_env(@env)
          super
        end

        def validate!
          super
          raise Informative, '未找到源码 podspec.' unless @podspec
          raise Informative, '请从组件根目录运行，或指定该目录下的 podspec.' unless File.dirname(File.expand_path(@podspec)) == Dir.pwd

          @spec = Specification.from_file(find_spec_file(@podspec))
          raise Informative, '只能发布组件根 podspec.' if @spec.subspec?
          CBin::Upload::Helper.new(@spec, @code_dependencies, @sources).preflight!
          binary_source
          code_source
        end

        def run
          auto_commit_if_needed! if @auto_commit

          arguments = [@podspec.to_s, "--env=#{@env}", "--configuration=#{@configuration}"]
          arguments << '--code-dependencies' if @code_dependencies
          arguments << "--sources=#{@sources}" if @sources
          arguments << '--no-clean' unless @clean

          archive = Archive.new(CLAide::ARGV.new(arguments))
          archive.validate!
          specs = archive.run
          unless specs.size == 1 && specs.first.name == @spec.name && specs.first.version == @spec.version
            raise Informative, '归档未生成预期组件；未上传任何制品.'
          end

          if @dry_run
            UI.puts "#{@spec.name} #{@spec.version} 预检与归档完成（dry-run，未上传制品或推送 spec）."
            return specs
          end

          begin
            ensure_git_tag! unless @skip_tag
            push_code_spec! unless @skip_code_spec
            CBin::Upload::Helper.new(@spec, @code_dependencies, @sources).upload
            push_git_branch_and_tag! if @push
          rescue Exception => error
            rollback_git_tag! if @created_tag
            raise error
          end
          UI.puts "#{@spec.name} #{@spec.version} 已发布到私有二进制仓库."
        end

        private

        def git_repo?
          File.exist?(File.join(Dir.pwd, '.git'))
        end

        def auto_commit_if_needed!
          return unless git_repo?

          status_out, status = Open3.capture2e('git', 'status', '--porcelain')
          return unless status.success?
          return if status_out.strip.empty?

          UI.puts "检测到本地未提交代码变更，正在自动暂存并提交..."
          _add_out, add_status = Open3.capture2e('git', 'add', '-A')
          raise Informative, "自动暂存本地变更失败" unless add_status.success?

          commit_msg = "chore: release #{@spec.name} #{@spec.version}"
          commit_out, commit_status = Open3.capture2e('git', 'commit', '-m', commit_msg)
          raise Informative, "自动提交本地变更失败: #{commit_out.strip}" unless commit_status.success?
          UI.puts "已自动提交本地变更: #{commit_msg}"
        end

        def push_git_branch_and_tag!
          return unless git_repo?

          remotes_out, status = Open3.capture2e('git', 'remote')
          return unless status.success?

          remotes = remotes_out.split("\n").map(&:strip).reject(&:empty?)
          return if remotes.empty?

          remote = remotes.include?('origin') ? 'origin' : remotes.first

          UI.puts "正在推送当前代码分支到 #{remote} HEAD..."
          push_out, push_status = Open3.capture2e('git', 'push', remote, 'HEAD')
          unless push_status.success?
            UI.warn "推送代码分支到 #{remote} 失败: #{push_out.strip}"
          end

          unless @skip_tag
            tag = @spec.version.to_s
            UI.puts "正在推送 Tag #{tag} 到 #{remote}..."
            tag_push_out, tag_push_status = Open3.capture2e('git', 'push', remote, tag, '--force')
            unless tag_push_status.success?
              UI.warn "推送 Tag #{tag} 到 #{remote} 失败: #{tag_push_out.strip}"
            end
          end
        end

        def ensure_git_tag!
          return unless git_repo?

          tag = @spec.version.to_s
          tag_rev, tag_status = Open3.capture2e('git', 'rev-parse', '-q', '--verify', "refs/tags/#{tag}")

          if tag_status.success?
            head_rev, head_status = Open3.capture2e('git', 'rev-parse', 'HEAD')
            if head_status.success? && tag_rev.strip == head_rev.strip
              UI.puts "本地 Git Tag #{tag} 已存在且指向当前最新提交."
              return
            else
              UI.warn "本地 Git Tag #{tag} 已存在但指向旧提交，正在强制更新到当前最新提交..."
              out, force_status = Open3.capture2e('git', 'tag', '-f', tag)
              raise Informative, "更新 Git Tag #{tag} 失败: #{out.strip}" unless force_status.success?
              @created_tag = true
              UI.puts "已更新本地 Git Tag #{tag} 指向当前最新提交."
              return
            end
          end

          out, create_status = Open3.capture2e('git', 'tag', tag)
          unless create_status.success?
            raise Informative, "创建 Git Tag #{tag} 失败: #{out.strip}"
          end
          @created_tag = true
          UI.puts "已创建本地 Git Tag #{tag}."
        end

        def rollback_git_tag!
          tag = @spec.version.to_s
          Open3.capture2e('git', 'tag', '-d', tag)
          UI.warn "发布失败，已回滚本地 Git Tag #{tag}."
        rescue StandardError => error
          UI.warn "回滚 Git Tag 失败: #{error.message}"
        end

        def push_code_spec!
          source = code_source
          return unless source.respond_to?(:repo) && source.repo

          spec_hash = JSON.parse(JSON.generate(@spec.to_hash))
          # 本地闭环模式下，将源码 spec 的 git 地址指向当前组件目录，确保 source 模式可直接按 tag 检出。
          if CBin.config.code_repo_url.to_s.start_with?('file://') && git_repo?
            spec_hash['source'] = { 'git' => "file://#{Dir.pwd}", 'tag' => @spec.version.to_s }
          end

          dir = CBin::Config::Builder.instance.local_psec_dir
          FileUtils.mkdir_p(dir)
          code_spec_json = File.join(dir, "#{@spec.name}.podspec.json")
          File.write(code_spec_json, Pod::Specification.from_hash(spec_hash).to_pretty_json)

          sources = sources_option(@code_dependencies, @sources)
          argvs = [
            code_spec_json,
            "--sources=#{sources}",
            '--skip-import-validation',
            '--skip-tests',
            '--allow-warnings',
            '--code-dependencies'
          ]
          argvs << '--allow-prerelease' if @allow_prerelease || (@spec.version.prerelease? rescue false)
          push = Pod::Command::Bin::Repo::Push.new(CLAide::ARGV.new(argvs))
          push.validate!
          push.run
        ensure
          FileUtils.rm_f(code_spec_json) if defined?(code_spec_json) && code_spec_json
        end
      end
    end
  end
end
