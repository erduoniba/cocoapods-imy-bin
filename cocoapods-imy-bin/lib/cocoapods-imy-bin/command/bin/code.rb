
module Pod
  class Command
    class Bin < Command
      class Code < Bin
        self.summary = '通过将二进制对应源码放置在临时目录中，让二进制出现断点时可以跳到对应的源码，方便调试。'

        self.description = <<-DESC
          通过将二进制对应源码放置在临时目录中，让二进制出现断点时可以跳到对应的源码，方便调试。
          在不删除二进制的情况下为某个组件添加源码调试能力，多个组件名称用空格分隔
        DESC

        self.arguments = [
            CLAide::Argument.new('NAME', false)
        ]
        def self.options
          [
              ['--all-clean', '删除所有已经下载的源码'],
              ['--clean', '删除所有指定下载的源码'],
              ['--list', '展示所有一级下载的源码以及其大小'],
              ['--source', '源码路径，本地路径,会去自动链接本地源码']
          ]
        end

        def initialize(argv)
          @codeSource =  argv.option('source') || nil
          @names = argv.arguments! unless argv.arguments.empty?
          @list = argv.flag?('list', false )
          @all_clean = argv.flag?('all-clean', false )
          @clean = argv.flag?('clean', false )

          @config = Pod::Config.instance

          super
        end


        def run

          podfile_lock = File.join(Pathname.pwd,"Podfile.lock")
          raise "podfile.lock,不存在，请先pod install/update" unless File.exist?(podfile_lock)
          @lockfile ||= Lockfile.from_file(Pathname.new(podfile_lock) )

          if @list
            list
          elsif @clean
            clean
          elsif @all_clean
            all_clean
          elsif @names
            add
          end

          if @list && @clean && @names
            raise "请选择您要执行的命令。"
          end
        end

        #==========================begin add ==============

        def add
          if @names == nil
            raise "请输入要调试组件名，多个组件名称用空格分隔"
          end

          @names.each do  |name|
            lib_file = get_lib_path(name)
            unless File.exist?(lib_file)
              raise "找不到 #{lib_file}"
            end
            UI.puts "#{lib_file}"

            target_path =  @codeSource || download_source(name)

            link(lib_file,target_path,name)
          end
        end

        #下载源码到本地
        def download_source(name)
          target_path =  File.join(source_root, name)
          UI.puts target_path
          FileUtils.rm_rf(target_path)

          find_dependency = find_dependency(name)
          # find_dependency.external_source = {:podspec => '/Users/denglibing3/.cocoapods/repos/erduoniba-hdpodrepo/HDStaticPod/0.1.0/HDStaticPod.podspec'}
          # find_dependency.requirement.requirements.first[1].version
          spec = fetch_external_source(find_dependency, @config.podfile,@config.lockfile, @config.sandbox,true )

          download_request = Pod::Downloader::Request.new(:name => name, :spec => spec)
          Downloader.download(download_request, Pathname.new(target_path), :can_cache => true)

          target_path
        end

        #找出依赖
        def find_dependency (name)
          find_dependency = nil
          @config.podfile.dependencies.each do |dependency|
            if dependency.root_name.downcase == name.downcase
              find_dependency = dependency
              break
            end
          end
          find_dependency
        end

        # 获取external_source 下的仓库
        # @return spec
        def fetch_external_source(dependency ,podfile , lockfile, sandbox,use_lockfile_options)
          source = ExternalSources.from_dependency(dependency, podfile.defined_in_file, true)
          source.fetch(sandbox)
        end


        #==========================link begin ==============

        #链接，.a文件位置， 源码目录，工程名=IMYFoundation
        def link(lib_file,target_path,basename)
          raw_dir = (`dwarfdump "#{lib_file}" | grep "AT_comp_dir" | head -1 | cut -d \\" -f2 `).chomp
          if raw_dir.empty?
            UI.puts "提示: 二进制未包含 DWARF AT_comp_dir 符号信息，可能为 Release 去符号产物。".yellow
            return
          end

          sub_path = "#{basename}/bin-archive/#{basename}"
          dir = raw_dir.sub(/\/Pods\/?\z/, "")
          dir = dir.gsub("#{basename}/Pods", "").chomp
          dir = dir.gsub(sub_path, "").chomp

          unless File.exist?(dir)
            begin
              FileUtils.mkdir_p(dir)
            rescue SystemCallError
              array = dir.split('/')
              if array.length > 3
                root_path = '/' + array[1] + '/' + array[2]
                unless File.exist?(root_path)
                  raise "由于权限不足，请手动创建#{root_path} 后重试"
                end
              end
            end
          end

          source_to_link = if File.directory?(File.join(target_path, basename))
            File.join(target_path, basename)
          else
            target_path
          end

          if Pathname.new(lib_file).extname == ".a"
            FileUtils.rm_rf(File.join(dir, basename))
            `ln -sf "#{source_to_link}" "#{dir}"`
          else
            FileUtils.rm_rf(File.join(dir, basename))
            `ln -sf "#{source_to_link}" "#{dir}/#{basename}"`
          end

          check(lib_file, dir, basename)
        end

        def check(lib_file,dir,basename)
          file = `dwarfdump "#{lib_file}" | grep -E "DW_AT_decl_file.*#{basename}.*(\\.m|\\.c|\\.swift|\\.h)" | head -1 | cut -d \\" -f2`.chomp
          if !file.empty? && !File.exist?(file)
            UI.puts "提示: 符号路径 #{file} 尚未完全匹配，请确认源码目录中包含该文件。".yellow
          else
            UI.puts "link successfully!"
            UI.puts "view linked source at path: #{dir}"
          end
        end

        def get_lib_path(name)
          dir = Pathname.new(File.join(Pathname.pwd, "Pods", name))
          raise "找不到 Pods/#{name} 目录" unless dir.exist?

          # 1. 直接匹配常见路径
          direct_candidates = [
            dir.join("lib#{name}.a"),
            dir.join(name),
            dir.join("#{name}.framework", name),
            dir.join("ios", "#{name}.framework", name)
          ]
          if found = direct_candidates.find { |p| p.file? }
            return found.to_s
          end

          # 2. XCFramework 结构匹配（优先考虑 simulator 切片，方便本地调试）
          xcframework_dirs = Dir.glob("#{dir}/**/*.xcframework")
          unless xcframework_dirs.empty?
            xcframework_dir = xcframework_dirs.first
            sim_candidates = Dir.glob("#{xcframework_dir}/*simulator*/**/#{name}").select { |f| File.file?(f) }
            sim_a = Dir.glob("#{xcframework_dir}/*simulator*/**/lib#{name}.a").select { |f| File.file?(f) }
            all_name = Dir.glob("#{xcframework_dir}/**/#{name}").select { |f| File.file?(f) }
            all_a = Dir.glob("#{xcframework_dir}/**/*.a").select { |f| File.file?(f) }

            picked = (sim_candidates + sim_a + all_name + all_a).first
            return picked if picked
          end

          # 3. 递归匹配二进制文件
          glob_candidates = Dir.glob("#{dir}/**/#{name}").select { |f| File.file?(f) }
          glob_a = Dir.glob("#{dir}/**/lib#{name}.a").select { |f| File.file?(f) }
          picked = (glob_candidates + glob_a).first
          return picked if picked

          # 4. 最后兜底
          lib_path = dir.join("lib#{name}.a")
          lib_path = dir.join(name) unless lib_path.exist?
          lib_path.to_s
        end

        #源码地址
        # def get_gitlib_iOS_path(name)
        #   "git@gitlab.xxx.com:iOS/#{name}.git"
        # end
        #要转换的地址，Github-iOS默认都是静态库
        # def git_gitlib_iOS_path
        #   'git@gitlab.xxx.com:Github-iOS/'
        # end


        #要转换的地址，Github-iOS默认都是静态库
        # def http_gitlib_GitHub_iOS_path
        #   'https://gitlab.xxx.com/Github-iOS/'
        # end

        #要转换的地址，iOS默认都是静态库
        # def http_gitlib_iOS_path
        #   'https://gitlab.xxx.com/iOS/'
        # end

        #==========================list begin ==============

        def list
          Dir.entries(source_root).each do |sub|
            UI.puts "- #{sub}" unless sub.include?('.')
          end
          UI.puts "加载完成"
        end


        #==========================clean begin ==============
        def all_clean
          FileUtils.rm_rf(source_root) if File.directory?(source_root)
          UI.puts "清理完成 #{source_root}"
        end

        def clean
          raise "请输入要删除的组件库" if @names.nil?
          @names.each do  |name|
            full_path = File.join(source_root,name)
            if File.directory?(full_path)
              FileUtils.rm_rf(full_path)
            else
              UI.puts "找不到 #{full_path}".yellow
            end
          end
          UI.puts "清理完成 #{@names.to_s}"
        end

        private

        def source_root
          dir = File.join(@config.cache_root,"Source")
          FileUtils.mkdir_p(dir) unless File.exist? dir
          dir
        end

      end
    end
  end
end
