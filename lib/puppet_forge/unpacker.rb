require 'pathname'
require 'find'
require 'puppet_forge/error'
require 'puppet_forge/tar'

module PuppetForge
  class Unpacker
    # Unpack a tar file into a specified directory
    #
    # @param filename [String] the file to unpack
    # @param target [String] the target directory to unpack into
    # @return [Hash{:symbol => Array<String>}] a hash with file-category keys pointing to lists of filenames.
    #   The categories are :valid, :invalid and :symlink
    def self.unpack(filename, target, tmpdir)
      inst = self.new(filename, target, tmpdir)
      file_lists = inst.unpack
      inst.move_into(Pathname.new(target))
      file_lists
    end

    # Set the owner/group of the target directory to those of the source
    # Note: don't call this function on Microsoft Windows
    #
    # @param source [Pathname] source of the permissions
    # @param target [Pathname] target of the permissions change
    def self.harmonize_ownership(source, target)
        FileUtils.chown_R(source.stat.uid, source.stat.gid, target)
    end

    # @param filename [String] the file to unpack
    # @param target [String] the target directory to unpack into
    def initialize(filename, target, tmpdir)
      @filename = filename
      @target = target
      @tmpdir = tmpdir
    end

    # @api private
    def unpack
      begin
        PuppetForge::Tar.instance.unpack(@filename, @tmpdir)
      rescue PuppetForge::ExecutionFailure => e
        raise RuntimeError, "Could not extract contents of module archive: #{e.message}"
      end
    end

    # @api private
    def move_into(dir)
      dir.rmtree if dir.exist?
      FileUtils.mv(root_dir, dir)
    ensure
      FileUtils.rmtree(@tmpdir)
    end

    # @api private
    def root_dir
      return @root_dir if @root_dir

      # Use Find.find instead of Dir[] for Windows long path support
      metadata_file = nil
      shortest_length = Float::INFINITY
      
      begin
        Find.find(@tmpdir) do |path|
          if File.basename(path) == 'metadata.json'
            if path.length < shortest_length
              metadata_file = path
              shortest_length = path.length
            end
          end
        end
      rescue Errno::ENAMETOOLONG => e
        # Even Find.find might fail, need to use Dir.each with manual recursion
        raise "Cannot traverse directory due to long paths: #{e.message}"
      end

      if metadata_file
        @root_dir = Pathname.new(metadata_file).dirname
      else
        raise "No valid metadata.json found!"
      end
    end
  end
end
