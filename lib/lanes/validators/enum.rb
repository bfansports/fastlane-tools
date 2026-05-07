require 'fastlane'

module Bfan
  module Lanes
    module Validators
      # Validates that a value is in an allowed set. Designed for use inside
      # FastlaneCore::ConfigItem verify_blocks but usable anywhere a hard fail
      # is the right response on bad input.
      module Enum
        def self.validate!(value, allowed:, key:)
          return if allowed.include?(value)

          FastlaneCore::UI.user_error!(
            "Invalid #{key} '#{value}'. Must be one of: #{allowed.join(', ')}"
          )
        end
      end
    end
  end
end
