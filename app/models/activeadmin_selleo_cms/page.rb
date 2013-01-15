module ActiveadminSelleoCms
  class Page < ActiveRecord::Base
    serialize :settings, Hash

    include ContentTranslation

    translates :title, :slug, :browser_title, :meta_keywords, :meta_description, fallbacks_for_empty_translations: true

    acts_as_nested_set

    attr_protected :id

    has_many :sections, as: :sectionable
    has_one :icon, as: :assetable
    has_one :header_image, as: :assetable
    has_many :attachments, as: :assetable
    has_many :assets, as: :assetable
    has_many :translations, foreign_key: :activeadmin_selleo_cms_page_id, dependent: :destroy, before_add: :set_nest

    accepts_nested_attributes_for :translations, :sections, :children, :icon, :header_image, :attachments

    validates_format_of :link_url, with: /^http/i, allow_blank: false, if: ->(page) { page.is_link_url }
    validates_presence_of :layout
    validates_associated :translations, :sections

    scope :show_in_menu, where(show_in_menu: true)
    scope :published, where(is_published: true)
    scope :not_published, where(is_published: false)
    scope :latest, ->(n) { published.reorder("published_at DESC").limit(n) }
    scope :most_read, ->(n) { published.reorder("views DESC").limit(n) }
    scope :with_layout, ->(layout_name) { where(layout: layout_name) }
    scope :with_setting_value, ->(key, value) { where("activeadmin_selleo_cms_pages.settings ~ '#{key}: #{value}'") }

    before_validation do
      self.slug = self.title.parameterize if title and slug.blank?
    end

    before_save do
      if is_published_changed?
        self.published_at = is_published ? Time.now : nil
      end
    end

    after_initialize do
      self.layout = Layout.all.first if new_record? and layout.blank?
    end

    def set_nest(t)
     t.activeadmin_selleo_cms_page ||= self
    end

    def method_missing(method, *args, &block)
      _method = (method.to_s[/(.*)\=$/,1] || method).to_sym
      unless (self.settings || {})[_method].nil?
        eval "
          def #{_method}
            (self.settings || {})[:#{_method}]
          end
          def #{_method}=(val)
            self.settings ||= {}
            val = true if val == '1'
            val = false if val == '0'
            self.settings[:#{_method}] = val
          end
          "
        send(method, *args)
      else
        super
      end
    end

    def initialize_missing_sections
      section_names.each do |section_name|
        sections.build(name: section_name) unless sections.detect{|section| section.name == section_name}
      end
    end

    def to_s
      title
    end

    def section_names
      begin
        File.open(Dir.glob(File.join(Rails.root, "app/views/layouts/#{layout}.html*")).first).read.scan(/yield\s*\:(\w+)/).flatten
      rescue
        []
      end
    end

    def to_param
      parent ? "#{parent.to_param}/#{slug}" : slug
    end

    def icon_url
      icon ? icon.url : 'http://placehold.it/120x90'
    end

    def header_image_url
      header_image ? header_image.url : 'http://placehold.it/770x385'
    end

    def roots
      Page.published.roots
    end

    def breadcrumb
      self_and_ancestors.map(&:title).join(' &raquo; ').html_safe
    end

    def url
      if is_link_url
        link_url
      elsif redirect_to_first_sub_page and children.published.any?
        "/#{I18n.locale}/#{children.published.first.to_param}"
      else
        "/#{I18n.locale}/#{to_param}"
      end
    end

    class Translation
      attr_protected :id

      validates :title, presence: true, if: ->(translation){ translation.locale.eql? I18n.locale }
      validates :slug, presence: true, format: { with: /^[a-z0-9\-_]+$/i }, if: ->(translation) { translation.locale.eql? I18n.locale }
      validate do |translation|
        if translation.class.joins(:activeadmin_selleo_cms_page).
            where(locale: locale, slug: slug, activeadmin_selleo_cms_pages: { parent_id: activeadmin_selleo_cms_page.parent_id }).all.reject{|p| p == self}.any?
          errors.add(:slug, :taken)
        end
      end
    end
  end
end
