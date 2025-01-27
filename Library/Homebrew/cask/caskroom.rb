# typed: true
# frozen_string_literal: true

require "utils/user"

module Cask
  # Helper functions for interacting with the `Caskroom` directory.
  #
  # @api private
  module Caskroom
    extend T::Sig

    sig { returns(Pathname) }
    def self.path
      @path ||= HOMEBREW_PREFIX/"Caskroom"
    end

    sig { returns(T::Boolean) }
    def self.any_casks_installed?
      return false unless path.exist?

      path.children.select(&:directory?).any?
    end

    sig { void }
    def self.ensure_caskroom_exists
      return if path.exist?

      sudo = !path.parent.writable?

      if sudo && !ENV.key?("SUDO_ASKPASS") && $stdout.tty?
        ohai "Creating Caskroom directory: #{path}",
             "We'll set permissions properly so we won't need sudo in the future."
      end

      SystemCommand.run("/bin/mkdir", args: ["-p", path], sudo: sudo)
      SystemCommand.run("/bin/chmod", args: ["g+rwx", path], sudo: sudo)
      SystemCommand.run("/usr/sbin/chown", args: [User.current, path], sudo: sudo)
      SystemCommand.run("/usr/bin/chgrp", args: ["admin", path], sudo: sudo)
    end

    sig { params(config: T.nilable(Config)).returns(T::Array[Cask]) }
    def self.casks(config: nil)
      return [] unless path.exist?

      path.children.select(&:directory?).sort.map do |path|
        token = path.basename.to_s

        begin
          if (tap_path = CaskLoader.tap_paths(token).first)
            CaskLoader::FromTapPathLoader.new(tap_path).load(config: config)
          elsif (caskroom_path = Pathname.glob(path.join(".metadata/*/*/*/*.rb")).first) &&
                (!Homebrew::EnvConfig.install_from_api? || !Homebrew::API::CaskSource.available?(token))
            CaskLoader::FromPathLoader.new(caskroom_path).load(config: config)
          else
            CaskLoader.load(token, config: config)
          end
        rescue CaskUnavailableError
          # Don't blow up because of a single unavailable cask.
          nil
        end
      end.compact
    end
  end
end
