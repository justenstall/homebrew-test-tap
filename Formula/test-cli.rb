# typed: false
# frozen_string_literal: true

require_relative "../lib/act3_download_strategy"

class TestCli < Formula
  include ACT3Homebrew

  desc "Changing the description!"
  homepage "https://github.com/justenstall"
  registry = "ghcr.io/justenstall/homebrew-test-tap/releases"
  # DO NOT EDIT OR RENAME: this variable is updated by the ACT3 Pipeline (you're welcome)
  repo = "test-cli@sha256:86b300b9e15731098b4aa92dde80d8381a4261c5e87f34c148505e3f54157e58"
  url "#{registry}/#{repo}", using: CraneManifestDownloadStrategy

  version "1.50.8"
  sha256 ACT3Homebrew.sha256_from_manifest_uri(url)

  bottle do
    root_url "https://ghcr.io/v2/justenstall/test-tap"
    rebuild 1
    sha256 cellar: :any_skip_relocation, ventura:      "fc3378517203e0fb0a45c4c75bff6c37515797a8bf2dbc7fe16d9c885f0676db"
    sha256 cellar: :any_skip_relocation, x86_64_linux: "8354277405bba4290437c3d61214c80ecf45c028d40b10650d5fa0ea1a9a413d"
  end

  def install
    bin.install "act3-pt"
    generate_completions_from_executable("#{bin}/act3-pt", "completion")

    # Generate manpages
    mkdir "man" do
      system "#{bin}/act3-pt", "gendocs", "-f", "man", "."
      man1.install Dir["*.1"]
      man5.install Dir["*.5"]
    end

    # Generate JSON Schema definitions
    mkdir share/"schemas" do
      system "#{bin}/act3-pt", "genschema", "."
    end
  end

  # Use opt_prefix/share here because "share" includes the version number
  # If the user adds the version number to their VS Code settings, the next time they update the tool,
  # the setting won't work
  def caveats
    <<~EOS
      Add the following to VS Code's settings.json file to enable YAML file validation:
        "yaml.schemas": {
          "file://#{opt_prefix}/share/schemas/configuration-schema.json": [
            "act3-pt-config.yaml",
            "act3/pt/config.yaml"
          ],
          "file://#{opt_prefix}/share/schemas/project-schema.json": ".act3-pt.yaml",
          "file://#{opt_prefix}/share/schemas/template-schema.json": ".act3-template.yaml"
        }
    EOS
  end

  test do
    system "#{bin}/act3-pt", "version"
  end
end
