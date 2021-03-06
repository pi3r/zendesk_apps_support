require 'pathname'
require 'erubis'
require 'json'

module ZendeskAppsSupport
  class Package

    DEFAULT_SCSS   = File.read(File.expand_path('../default_styles.scss', __FILE__))
    SRC_TEMPLATE = Erubis::Eruby.new( File.read(File.expand_path('../src.js.erb', __FILE__)) )

    attr_reader :root

    def initialize(dir)
      @root = Pathname.new(File.expand_path(dir))
    end

    def validate
      Validations::Manifest.call(self) +
        Validations::Source.call(self) +
        Validations::Templates.call(self) +
        Validations::Translations.call(self) +
        Validations::Stylesheets.call(self)
    end

    def files
      non_tmp_files
    end

    def template_files
      files.select { |f| f =~ /^templates\/.*\.hdbs$/ }
    end

    def translation_files
      files.select { |f| f =~ /^translations\// }
    end

    def manifest_json
      JSON.parse(File.read(File.join(root, "manifest.json")), :symbolize_names => true)
    end

    def readified_js(app_name, app_id, asset_url_prefix, settings={})
      manifest = manifest_json
      source = File.read(File.join(root, "app.js"))
      name = app_name || manifest[:name] || 'Local App'
      location = manifest[:location]
      app_class_name = "app-#{app_id}"
      author = manifest[:author]
      translations = JSON.parse(File.read(File.join(root, "translations/en.json")))
      framework_version = manifest[:frameworkVersion]
      templates = compiled_templates(app_id, asset_url_prefix)

      settings["title"] = name

      SRC_TEMPLATE.result(
          :name => name,
          :source => source,
          :location => location,
          :asset_url_prefix => asset_url_prefix,
          :app_class_name => app_class_name,
          :author => author,
          :translations => translations,
          :framework_version => framework_version,
          :templates => templates,
          :settings => settings,
          :app_id => app_id
      )
    end

    def customer_css
      css_file = File.join(root, 'app.css')
      customer_css = File.exist?(css_file) ? File.read(css_file) : ""
    end

    private

    def compiled_templates(app_id, asset_url_prefix)
      compiled_css = ZendeskAppsSupport::StylesheetCompiler.new(DEFAULT_SCSS + customer_css, app_id, asset_url_prefix).compile

      templates = begin
        Dir["#{root.to_s}/templates/*.hdbs"].inject({}) do |h, file|
          str = File.read(file)
          str.chomp!
          h[File.basename(file, File.extname(file))] = str
          h
        end
      end

      templates.tap do |templates|
        templates['layout'] = "<style>\n#{compiled_css}</style>\n#{templates['layout']}"
      end
    end

    def non_tmp_files
      files = []
      Dir[ root.join('**/**') ].each do |f|
        next unless File.file?(f)
        relative_file_name = f.sub(/#{root}\/?/, '')
        next if relative_file_name =~ /^tmp\//
        files << AppFile.new(self, relative_file_name)
      end
      files
    end
  end
end
