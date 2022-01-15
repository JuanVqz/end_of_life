require "dry-monads"

module EolRuby
  class Repository
    class << self
      include Dry::Monads[:result, :maybe]

      def fetch(language:, user: nil)
        github_client.fmap do |github|
          user ||= github.user.login
          response = github.search_repositories("user:#{user} language:#{language}", per_page: 100)
          warn "Incomplete results: we only search 100 repos at a time" if response.incomplete_results

          response.items.map do |repo|
            Repository.new(
              full_name: repo.full_name,
              url: repo.html_url
            )
          end
        rescue => e
          Failure("Unexpected error: #{e}")
        end
      end

      def github_client
        @github_client ||= Maybe(ENV["GITHUB_TOKEN"])
          .to_result
          .fmap { |token| Octokit::Client.new(access_token: token) }
          .or { Failure("Please set GITHUB_TOKEN environment variable") }
      end
    end

    attr :full_name, :url

    def initialize(full_name:, url:)
      @full_name = full_name
      @url = url
    end

    def eol_ruby?
      ruby_version&.eol?
    end

    def ruby_version
      return @ruby_version if defined?(@ruby_version)

      @ruby_version = ruby_versions.min
    end

    private

    def ruby_versions
      return @ruby_versions if defined?(@ruby_versions)

      @ruby_versions = begin
        ruby_version_files = [
          fetch_file(".ruby-version"),
          fetch_file("Gemfile"),
          fetch_file("Gemfile.lock")
        ].compact

        ruby_version_files.filter_map { |file| parse_version_file(file) }
      end
    end

    def github_client
      self.class.github_client
    end

    def fetch_file(file_path)
      github_client
        .fmap { |github| github.contents(full_name, path: file_path) }
        .value_or(nil)
    rescue Octokit::NotFound
      nil
    end

    def parse_version_file(file)
      RubyVersion.from_file(file_name: file.name, content: decode_file(file))
    end

    def decode_file(file)
      return file if file.encoding.nil?
      return Base64.decode64(file.content) if file.encoding == "base64"

      raise "Unsupported encoding: #{file.encoding.inspect}"
    end
  end
end
