require 'fileutils'
require 'tempfile'
require 'yaml'

module CBin
  module PodModes
    FILENAME = '.imy-bin-modes.yml'.freeze
    MODES = %w[local source binary branch].freeze
    REMOTE_MODES = %w[source binary].freeze
    NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._+-]{0,127}\z/

    def self.path(project_root)
      File.join(project_root.to_s, FILENAME)
    end

    def self.read(project_root)
      filename = path(project_root)
      return {} unless File.file?(filename)

      modes = YAML.safe_load(File.read(filename), permitted_classes: [], aliases: false)
      unless modes.is_a?(Hash) && modes.all? { |name, mode| valid_name?(name) && MODES.include?(mode) }
        raise Pod::Informative, "#{filename} 只能包含组件名到 local/source/binary 的映射."
      end
      modes
    rescue Psych::Exception => error
      raise Pod::Informative, "无法读取 #{filename}: #{error.message}"
    end

    def self.write(project_root, modes)
      filename = path(project_root)
      if modes.empty?
        FileUtils.rm_f(filename)
        return
      end
      Tempfile.create(['.imy-bin-modes-', '.tmp'], project_root.to_s) do |file|
        file.write(modes.sort.to_h.to_yaml)
        file.flush
        File.rename(file.path, filename)
      end
    end

    def self.reset(project_root)
      FileUtils.rm_f(path(project_root))
    end

    def self.valid_name?(name)
      name.is_a?(String) && NAME_PATTERN.match?(name)
    end
  end
end
