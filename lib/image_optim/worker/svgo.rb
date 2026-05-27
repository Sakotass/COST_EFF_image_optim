# frozen_string_literal: true

require 'image_optim/option_helpers'
require 'image_optim/worker'
require 'fspath'

class ImageOptim
  class Worker
    # https://github.com/svg/svgo
    class Svgo < Worker
      PLUGIN_NAME_R = /\A[a-zA-Z]+\z/.freeze

      DISABLE_PLUGINS_OPTION =
      option(:disable_plugins, [], 'List of plugins to disable') do |v|
        parse_plugin_names(v)
      end

      ENABLE_PLUGINS_OPTION =
      option(:enable_plugins, [], 'List of plugins to enable') do |v|
        parse_plugin_names(v)
      end

      ALLOW_LOSSY_OPTION =
      option(:allow_lossy, false, 'Allow precision option'){ |v| !!v }

      PRECISION_OPTION =
      option(:precision, 3, 'Number of digits in the fractional part ' \
                            '`0`..`20`, ignored in default/lossless mode') \
                            do |v, opt_def|
        if allow_lossy
          OptionHelpers.limit_with_range(v.to_i, 0..20)
        else
          if v != opt_def.default
            warn "#{self.class.bin_sym} #{opt_def.name} #{v} ignored " \
                 'in default/lossless mode'
          end
          opt_def.default
        end
      end

      def optimize(src, dst, options = {})
        args = %W[
          --input #{src}
          --output #{dst}
        ]
        if resolve_bin!(:svgo).version >= '2.0.0'
          unless disable_plugins.empty? && enable_plugins.empty?
            config_file = plugins_config_file
            args.unshift "--config=#{config_file.path}"
          end
        else
          disable_plugins.each do |plugin_name|
            args.unshift "--disable=#{plugin_name}"
          end
          enable_plugins.each do |plugin_name|
            args.unshift "--enable=#{plugin_name}"
          end
        end
        args.unshift "--precision=#{precision}" if allow_lossy
        execute(:svgo, args, options) && optimized?(src, dst)
      end

    private

      def parse_plugin_names(value)
        Array(value).map(&:to_s).select do |name|
          if name =~ PLUGIN_NAME_R
            true
          else
            warn "Doesn't look like svgo plugin name: #{name}"
          end
        end
      end

      def plugins_config_file
        @plugins_config_file ||= FSPath.temp_file(%w[image_optim .js]).tap do |config_file|
          config_file.puts 'export default {'
          config_file.puts '  plugins: ['
          config_file.puts '    {'
          config_file.puts '      name: \'preset-default\','
          config_file.puts '      params: {'
          config_file.puts '        overrides: {'
          disable_plugins.each do |plugin_name|
            config_file.puts "          #{plugin_name}: false,"
          end
          config_file.puts '        }'
          config_file.puts '      }'
          config_file.puts '    },'
          enable_plugins.each do |plugin_name|
            config_file.puts "  '#{plugin_name}',"
          end
          config_file.puts '  ]'
          config_file.puts '};'
          config_file.close
        end
      end
    end
  end
end
