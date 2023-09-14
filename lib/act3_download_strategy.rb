# frozen_string_literal: true

require 'download_strategy'
require 'json'
require 'os'
require 'digest/sha2'
require 'pathname'
require 'uri'

module ACT3Homebrew
  module_function

  # Platform gets os/arch
  def get_platform()
    if OS.mac?
      os = 'darwin'
    else
      os = 'linux'
    end
  
    if Hardware::CPU.arm?
      arch = 'arm64'
    else
      arch = 'amd64'
    end
  
    platform = "#{os}/#{arch}"

    odebug 'Platform', platform

    platform
  end

  # Returns directory containing the docker-credential-helper installs
  def get_docker_credential_helper_dir()
    # Check for each platform's helper
    linux_credential_path = ensure_executable! 'docker-credential-secretservice', formula_name = 'docker-credential-helper', reason: "OCI registry authentication"
    darwin_credential_path = ensure_executable! 'docker-credential-osxkeychain', formula_name = 'docker-credential-helper', reason: "OCI registry authentication"

    docker_credential_dir = ""
    if darwin_credential_path.exist?
      docker_credential_dir = darwin_credential_path.dirname
    elsif linux_credential_path.exist?
      docker_credential_dir = linux_credential_path.dirname
    end

    odebug "Docker Credential Helper Directory", docker_credential_dir

    docker_credential_dir
  end

  # Returns the path to the crane executable
  def get_crane_path(reason: "")
    crane_path = ensure_executable! 'crane', reason: reason
    odebug 'Crane Path', crane_path
    crane_path
  end

  #TODO: make sure this works in non-bash shells
  def _crane_command(docker_credential_dir, crane_path, command)
    # Command with PATH cooked up to contain the docker credential helper
    # PATH is set to allow credentials helpers to be found by crane
    # DBUS_SESSION_BUS_ADDRESS is set to preserve the dbus session for use by secret service password managers
    #   this was needed for linux users using the secretservice credStore in docker config
    system "DBUS_SESSION_BUS_ADDRESS=#{ENV['HOMEBREW_DBUS_SESSION_BUS_ADDRESS']} PATH=$PATH:#{docker_credential_dir} #{crane_path} #{command}"
  end

  def blob_digest_from_manifest(manifest)
    manifest = JSON.parse(manifest)
    layers = manifest['layers'] if manifest.key?('layers')
    raise "No available artifacts in manifest #{url} for platform #{@platform}" if layers.empty?

    blob = layers[0]

    odebug "Blob"
    blob_digest = blob['digest'] if blob.key?('digest')
  end

  def sha256_from_manifest_uri(manifest_uri)
    docker_credential_dir = get_docker_credential_helper_dir()
    crane_path = get_crane_path(reason: "Checksum verification")
    platform = get_platform()

    sha256 = Digest::SHA2.new
    
    split_uri = manifest_uri.split('@', -1)
    base_uri = split_uri[0]

    Dir.mktmpdir do |tmpdir|
      index_location = "#{tmpdir}/index.json"
      odebug "Downloading index to #{index_location}"

      index_file = Pathname.new(index_location)
      redirect_stdout(index_location) do
        success = _crane_command docker_credential_dir, crane_path, "manifest #{manifest_uri}"
        if !success
          opoo "Couldn't retrieve checksum, skipping checksum verification"
          return ""
        end
      end # image index retrieval

      odebug 'Image index', index_file.read

      # Get digest from manifest_uri and verify against checksum
      index_digest = Checksum.new(split_uri[1].delete_prefix('sha256:'))
      index_file.verify_checksum(index_digest)

      # Get the image digest
      image_digest_location = "#{tmpdir}/image_digest.txt"
      odebug "Downloading image digest to #{index_location}"

      image_digest_file = Pathname.new(image_digest_location)
      redirect_stdout(image_digest_location) do
        # success = system "crane digest --platform #{platform} #{manifest_uri}"
        success = _crane_command docker_credential_dir, crane_path, "digest --platform #{platform} #{manifest_uri}"
        if !success
          opoo "Couldn't retrieve checksum, skipping checksum verification"
          return ""
        end
      end # end image digest command

      image_digest = image_digest_file.read

      odebug 'Image digest', image_digest

      image_digest = Checksum.new(image_digest.strip.delete_prefix('sha256:'))

      # Get the image manifest
      image_location = "#{tmpdir}/image.json"
      odebug "Downloading index manifest to #{index_location}"

      image_file = Pathname.new(image_location)
      redirect_stdout(image_location) do
        # success = system "crane manifest #{base_uri}@sha256:#{image_digest}"
        success = _crane_command docker_credential_dir, crane_path, "manifest #{base_uri}@sha256:#{image_digest}"
        if !success
          opoo "Couldn't retrieve checksum, skipping checksum verification"
          return ""
        end
      end # end image manifest

      image = image_file.read
      
      odebug 'Image manifest', image
      
      # Verify image checksum
      image_file.verify_checksum(image_digest)

      # Get blob digest from the image manifest
      blob_digest = blob_digest_from_manifest(image).delete_prefix('sha256:')
    end # end tempdir
  end
end

# CraneBlobDownloadStrategy does a blob download using crane
class CraneBlobDownloadStrategy < AbstractFileDownloadStrategy
  include ACT3Homebrew

  # Platform of the downloading computer, in OCI format (OS/ARCH).
  #
  # @api public
  sig { returns(String) }
  attr_reader :platform

  # Path to crane executable.
  #
  # @api public
  sig { returns(String) }
  attr_reader :crane_path

  # Directory containing the installed docker credential helpers (docker-credential-helper).
  #
  # @api public
  sig { returns(String) }
  attr_reader :docker_credential_dir

  def initialize(url, name, version, **meta)
    super
    @platform = ACT3Homebrew.get_platform()
    @crane_path = get_crane_path(reason: "OCI registry retrieval")
    @docker_credential_dir = get_docker_credential_helper_dir()
  end

  # Download and cache the file at {#cached_location}.
  #
  # @api public
  def fetch(*)
    ohai "Downloading blob #{url}"

    cached_location_exists = cached_location.exist?

    fresh = if cached_location_exists
            elsif version.respond_to?(:latest?)
              !version.latest?
            else
              true
            end

    # Handling of previous downloads, copied from: 
    # https://github.com/Homebrew/brew/blob/c7bd51b9957e83393aedeca3f1afecc33a5be19c/Library/Homebrew/download_strategy.rb#L403
    if cached_location_exists && fresh
      ohai "Already downloaded: #{cached_location}"
    else
      download_blob(url)

      ignore_interrupts do
        cached_location.dirname.mkpath
        temporary_path.rename(cached_location)
        symlink_location.dirname.mkpath
      end
    end

    FileUtils.ln_s cached_location.relative_path_from(symlink_location.dirname), symlink_location, force: true
  end

  def download_blob(blob_url)
    redirect_stdout(temporary_path) do
      odie "Couldn't download blob" unless crane_command "blob #{blob_url}"
    end
  end

  def parse_basename(url, search_query: true)
    platform_arr = @platform.split('/', -1)
    "#{name}--#{platform_arr[0]}--#{platform_arr[1]}.tar.gz"
  end

  def crane_command(command)
    ACT3Homebrew._crane_command @docker_credential_dir, @crane_path, command
  end
end

# CraneManifestDownloadStrategy does a blob download using crane
class CraneManifestDownloadStrategy < CraneBlobDownloadStrategy
  include ACT3Homebrew

  # Download and cache the file at {#cached_location}.
  #
  # @api public
  def fetch(*)
    blob_url = get_blob_uri(url)
    @url = blob_url
    super
  end

  def get_blob_uri(url)
    manifest = nil

    ohai "Downloading manifest list #{url}"

    Dir.mktmpdir do |tmpdir|
      index_location = "#{tmpdir}/#{name}--v#{version}--index.json"
      odebug "Downloading index to #{index_location}"

      index_file = Pathname.new(index_location)
      redirect_stdout(index_location) do
        success = crane_command "--platform #{@platform} manifest #{url}"
        if !success
          odie "Couldn't retrieve image manifest"
        end 
      end

      manifest = index_file.read

      odebug "Index manifest", manifest
    end

    blob_digest = ACT3Homebrew.blob_digest_from_manifest(manifest)

    reg_url = url.split('@', -1)

    prefix = reg_url[0]

    blob_url = "#{prefix}@#{blob_digest}"
  end
end
