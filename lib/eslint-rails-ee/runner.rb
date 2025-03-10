require 'action_view'
require 'colorize'

module ESLintRails
  class Runner
    include ActionView::Helpers::JavaScriptHelper

    JAVASCRIPT_EXTENSIONS = %w[.js .jsx .es6].freeze

    def initialize(file)
      @file   = normalize_infile(file)
      @assets = assets
      puts "Running ESLint | [#{@assets.size } file(s)]".white.on_black.italic
      print 'Progress: ['.white.on_black
    end

    def run(should_autocorrect=false)
      warnings = @assets.map do |asset|
        generate_warnings(asset, should_autocorrect).tap { |warnings| output_progress(warnings) }
      end

      print "]".white.on_black
      puts
      puts

      warnings.flatten
    end

    private

    def normalize_infile(file)
      file = file.to_s.gsub(/^app\/assets\/javascripts\//, '') # Remove beginning of asset path
      file = Pathname.new("#{Dir.pwd}/app/assets/javascripts/#{file}") # Ensure path is absolute
      file = Pathname.new("#{file}.js") if !file.directory? && file.extname.empty? # Make sure it has an extension
      file
    end

    def assets
      all_js_assets = Rails.application.assets.each_file.to_a.map { |path| Pathname.new(path) }.select do |asset|
        JAVASCRIPT_EXTENSIONS.include?(asset.extname)
      end

      assets = all_js_assets.select{|a| is_descendant?(@file, a)}

      assets.reject{|a| a.to_s =~ /eslint.js|vendor|gems|min.js|editorial/ }
    end

    def eslint_js
      @eslint_js ||= Rails.application.assets['eslint'].to_s
    end

    def eslint_plugin_js
      @eslint_plugin_js ||= begin
        plugins.map do |plugin_name|
          Rails.application.assets["plugins/eslint-plugin-#{plugin_name}"].to_s
        end.join('\n')
      end
    end

    def plugins
      JSON.parse(Config.read)['plugins'] || []
    end

    def warning_hashes(file_content, relative_path, should_autocorrect=false)
      if !should_autocorrect
        ExecJS.eval <<-JS
          function () {
            window = this;
            #{eslint_js};
            #{eslint_plugin_js};
            return new eslint().verify('#{escape_javascript(file_content)}', #{Config.read});
          }()
        JS
      else
        hsh = ExecJS.eval <<-JS
        function () {
          window = this;
          #{eslint_js};
          #{eslint_plugin_js};
          return new eslint().verifyAndFix('#{escape_javascript(file_content)}', #{Config.read});
        }()
        JS
        File.write(relative_path, hsh['output']) if !hsh['output'].nil?
        hsh['messages']
      end
    end

    def generate_warnings(asset, should_autocorrect=false)
      relative_path = asset.relative_path_from(Pathname.new(Dir.pwd))
      file_content  = asset.read

      warning_hashes(file_content, relative_path, should_autocorrect).map do |hash|
        ESLintRails::Warning.new(relative_path, hash)
      end
    end

    def output_progress(warnings)
      print case file_severity(warnings)
            when :high
              '!'.red.on_black.blink
            when :low
              '?'.yellow.on_black.italic
            else
              '='.green.on_black
            end
    end

    def file_severity(warnings)
      warnings.map(&:severity).uniq.sort.first
    end

    def is_descendant?(a, b)
      a_list = a.to_s.split('/')
      b_list = b.to_s.split('/')

      b_list[0..a_list.size-1] == a_list
    end
  end
end
