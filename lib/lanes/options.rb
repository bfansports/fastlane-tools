require 'fastlane'
require_relative 'validators/enum'

module Bfan
  module Lanes
    module Options
      Item = FastlaneCore::ConfigItem

      # Bfan::Options::Enum
      #
      # A FastlaneCore::ConfigItem that auto-validates its value against `allowed`.
      # All other ConfigItem kwargs (optional:, default_value:, conflicting_options:,
      # short_option:, env_name:, etc.) pass through unchanged.
      #
      # If you supply your own `verify_block:`, it composes with the enum check —
      # the enum check runs first, then your block. Both must pass.
      class Enum < FastlaneCore::ConfigItem
        def initialize(key:, allowed:, description: nil, **opts)
          user_verify = opts.delete(:verify_block)

          combined_verify = proc do |value|
            Validators::Enum.validate!(value, allowed: allowed, key: key)

            if user_verify
              user_verify.call(value)
            end
          end

          super(
            key: key,
            description: description || "One of: #{allowed.join(', ')}",
            verify_block: combined_verify,
            **opts
          )
        end
      end

      def self.parse(items, raw_options)
        FastlaneCore::Configuration.create(items, raw_options || {})
      end
    end
  end
end
