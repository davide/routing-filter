# The RoutesLocalization filter extracts segments matching /:locale from the
# beginning of the recognized path and exposes the locale parameter as
# params[:locale]. When a path is generated the filter adds the segments to the
# path accordingly if the locale parameter is passed to the url helper.
#
#   incoming url: /pt-PT/products/latest
#   filtered url: /products/latest
#   params:       params[:locale] = 'pt-PT'
#
# While generating links this filter will also translate path segments using the
# hierarchical translation structure specified in the I18n "url" key (see below).
# Given a file pt-PT.yml containing:
#   pt-PT:
#     url:
#       products:
#         _: produtos
#         latest:
#           _: novidades
# and default_locale => :pt-PT the path "/products/latest" would become:
#   /produtos/novidades
# For non-default locales the locale would be prepended:
#   /es/productos/recientes
#
# You can install the filter like this:
#
#   # in config/routes.rb
#   Rails.application.routes.draw do
#     filter :locale
#   end
#
# To make your named_route helpers or url_for add the pagination segments you
# can use:
#
#   products_path(:locale => 'de')
#   url_for(:products, :locale => 'de'))

require 'i18n'

module RoutingFilter
  class RoutesLocalization < Filter
    @@include_default_locale = true
    cattr_writer :include_default_locale

    class << self
      def include_default_locale?
        @@include_default_locale
      end

      def locales
        @@locales ||= I18n.available_locales.map(&:to_sym)
      end

      def locales=(locales)
        @@locales = locales.map(&:to_sym)
      end

      def locales_pattern
        @@locales_pattern ||= %r(^/(#{self.locales.map { |l| Regexp.escape(l.to_s) }.join('|')})(?=/|$))
      end

      def translations_tree
        @tts ||= {}
        @tts[I18n.locale] ||= stringify_keys(I18n.t("url"))
      end

      def reverse_translations_tree
        @@rtts ||= {}
        @@rtts[I18n.locale] ||= invert_tree(translations_tree)
      end

      protected

      def stringify_keys(node)
        return node if node.is_a? String
        node.inject({}) do |acc, (k,v)|
          acc[k.to_s] = stringify_keys(v)
          acc
        end
      end

      def invert_tree(mapper = {})
        result = {}
        mapper.each_pair do |k, v|
          if v.is_a?(Hash)
            name = v["_"]
            result[name] = invert_tree(v)
            result[name]["_"] = k
          end
        end
        result
      end
    end

    def around_recognize(path, env, &block)
      locale = extract_segment!(self.class.locales_pattern, path) # remove the locale from the beginning of the path
      untranslate_path(path, locale)
      yield.tap do |params|                                       # invoke the given block (calls more filters and finally routing)
        params[:locale] = locale if locale                        # set recognized locale to the resulting params hash
      end
    end

    def around_generate(params, &block)
      locale = params.delete(:locale)                             # extract the passed :locale option
      locale = I18n.locale if locale.nil?                         # default to I18n.locale when locale is nil (could also be false)
      locale = nil unless valid_locale?(locale)                   # reset to no locale when locale is not valid

      yield.tap do |result|
        translate_path(result, locale)
        prepend_segment!(result, locale) if prepend_locale?(locale)
      end
    end

    protected

      def valid_locale?(locale)
        locale && self.class.locales.include?(locale.to_sym)
      end

      def default_locale?(locale)
        locale && locale.to_sym == I18n.default_locale.to_sym
      end

      def prepend_locale?(locale)
        locale && (self.class.include_default_locale? || !default_locale?(locale))
      end

      def translate_path(path, locale)
        return if !locale
        I18n.with_locale(locale) do
          i18n_tt = I18n.t("url", :default => "")
          return if i18n_tt == ""
          tt = self.class.translations_tree
          match_with_tree(path, tt)
        end
      end

      def untranslate_path(path, locale)
        locale = I18n.default_locale if !locale
        I18n.with_locale(locale) do
          i18n_tt = I18n.t("url", :default => "")
          return if i18n_tt == ""
          rtt = self.class.reverse_translations_tree
          match_with_tree(path, rtt)
        end
      end

      def match_with_tree(path, tree)
        segments = path.split("/")
        segments.shift
        n_path = ""
        prefix = []
        while (segment = segments.shift) do
          match = tree_segment_node(tree, prefix, segment)
          prefix += [segment] if match != segment
          n_path += "/#{match}"
        end
        path.sub! path, n_path if !n_path.empty?
      end

      def tree_segment_node(tree_node, prefix, segment)
        segments = prefix + [segment, "_"]
        while (segment = segments.shift) do
          tree_node = tree_node[segment]
          return segment if tree_node.nil?
        end
        return segment if tree_node.is_a? Hash
        tree_node
      end
  end
end
