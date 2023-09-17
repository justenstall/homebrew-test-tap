# typed: false
# frozen_string_literal: true

class JustenstallBundle < Formula
  desc "This is my Brewfile installer!"
  homepage "https://github.com/justenstall"
  url "https://github.com/justenstall/homebrew-test-tap.git", 
  	using: :git,
	branch: "main"
  version "0.0.1"

  def install
    system "#{bin}/brew", "bundle", "justenstall-bundle"
  end

#   # Use opt_prefix/share here because "share" includes the version number
#   # If the user adds the version number to their VS Code settings, the next time they update the tool,
#   # the setting won't work
#   def caveats
#     <<~EOS
#       Add the following to VS Code's settings.json file to enable YAML file validation:
#         "yaml.schemas": {
#           "file://#{opt_prefix}/share/schemas/configuration-schema.json": [
#             "act3-pt-config.yaml",
#             "act3/pt/config.yaml"
#           ],
#           "file://#{opt_prefix}/share/schemas/project-schema.json": ".act3-pt.yaml",
#           "file://#{opt_prefix}/share/schemas/template-schema.json": ".act3-template.yaml"
#         }
#     EOS
#   end

#   test do
#     system "#{bin}/act3-pt", "version"
#   end
end
