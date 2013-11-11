require File.join(File.dirname(__FILE__), 'windows', 'helper')
require File.join(File.dirname(__FILE__), 'windows', 'constants')
require File.join(File.dirname(__FILE__), 'windows', 'structs')
require File.join(File.dirname(__FILE__), 'windows', 'functions')
require 'pp'

class File::Stat
  include Windows::Stat::Constants
  include Windows::Stat::Structs
  include Windows::Stat::Functions
  include Comparable

  # We have to undefine these first in order to avoid redefinition warnings.
  undef_method :atime, :ctime, :mtime, :blksize, :blockdev?, :blocks, :chardev?
  undef_method :dev, :directory?, :executable?, :executable_real?, :file?
  undef_method :ftype, :gid, :grpowned?, :ino, :mode, :nlink, :owned?
  undef_method :pipe?, :readable?, :rdev
  undef_method :readable_real?, :size, :size?, :socket?, :symlink?, :uid
  undef_method :writable?, :writable_real?, :zero?
  undef_method :<=>, :inspect, :pretty_print

  # A Time object containing the last access time.
  attr_reader :atime

  # A Time object indicating when the file was last changed.
  attr_reader :ctime

  # A Time object containing the last modification time.
  attr_reader :mtime

  # The native filesystems' block size.
  attr_reader :blksize

  # The number of native filesystem blocks allocated for this file.
  attr_reader :blocks

  # The serial number of the file's volume.
  attr_reader :dev

  # The file's unique identifier. Only valid for regular files.
  attr_reader :ino

  # Integer representing the permission bits of the file.
  attr_reader :mode

  # The number of hard links to the file.
  attr_reader :nlink

  # The size of the file in bytes.
  attr_reader :size

  # The version of the win32-file-stat library
  VERSION = '1.4.0'

  # Creates and returns a File::Stat object, which encapsulate common status
  # information for File objects on MS Windows sytems. The information is
  # recorded at the moment the File::Stat object is created; changes made to
  # the file after that point will not be reflected.
  #
  def initialize(file)
    raise TypeError unless file.is_a?(String)

    path  = file.tr('/', "\\")
    @path = path

    @user_sid = get_file_sid(file, OWNER_SECURITY_INFORMATION)
    @grp_sid  = get_file_sid(file, GROUP_SECURITY_INFORMATION)

    @uid = @user_sid.split('-').last.to_i
    @gid = @grp_sid.split('-').last.to_i

    @owned = @user_sid == get_current_process_sid(TokenUser)
    @grpowned = @grp_sid == get_current_process_sid(TokenGroups)

    begin
      # The handle returned will be used by other functions
      handle = get_handle(path)

      @blockdev = get_blockdev(path)
      @blksize  = get_blksize(path)

      if handle
        @filetype = get_filetype(handle)
        @chardev  = @filetype == FILE_TYPE_CHAR
        @regular  = @filetype == FILE_TYPE_DISK
        @pipe     = @filetype == FILE_TYPE_PIPE
      else
        @chardev = false
        @regular = false
        @pipe    = false
      end

      fpath = path.wincode

      if handle == nil || ((@blockdev || @chardev || @pipe) && GetDriveType(fpath) != DRIVE_REMOVABLE)
        data = WIN32_FIND_DATA.new
        CloseHandle(handle) if handle

        handle = FindFirstFile(fpath, data)

        if handle == INVALID_HANDLE_VALUE
          raise SystemCallError.new('FindFirstFile', FFI.errno)
        end

        FindClose(handle)
        handle = nil

        @nlink = 1 # Default from stat/wstat function.
        @ino   = nil
        @dev   = nil
      else
        data = BY_HANDLE_FILE_INFORMATION.new

        unless GetFileInformationByHandle(handle, data)
          raise SystemCallError.new('GetFileInformationByHandle', FFI.errno)
        end

        @nlink = data[:nNumberOfLinks]
        @ino   = (data[:nFileIndexHigh] << 32) | data[:nFileIndexLow]
        @dev   = data[:dwVolumeSerialNumber]
      end

      # Not supported and/or meaningless on MS Windows
      @dev_major     = nil
      @dev_minor     = nil
      @readable      = true # TODO: Make this work
      @readable_real = true # TODO: Same as readable
      @rdev_major    = nil
      @rdev_minor    = nil
      @setgid        = false
      @setuid        = false
      @sticky        = false
      @writable      = true  # TODO: Make this work
      @writable_real = true  # TODO: Same as writeable

      # Originally used GetBinaryType, but it only worked
      # for .exe files, and it could return false positives.
      @executable = %w[.bat .cmd .com .exe].include?(File.extname(@path).downcase)

      # Set blocks equal to size / blksize, rounded up
      case @blksize
        when nil
          @blocks = nil
        when 0
          @blocks = 0
        else
          @blocks  = (data.size.to_f / @blksize.to_f).ceil
      end

      @attr  = data[:dwFileAttributes]
      @atime = Time.at(data.atime)
      @ctime = Time.at(data.ctime)
      @mtime = Time.at(data.mtime)
      @size  = data.size

      @archive       = @attr & FILE_ATTRIBUTE_ARCHIVE > 0
      @compressed    = @attr & FILE_ATTRIBUTE_COMPRESSED > 0
      @directory     = @attr & FILE_ATTRIBUTE_DIRECTORY > 0
      @encrypted     = @attr & FILE_ATTRIBUTE_ENCRYPTED > 0
      @hidden        = @attr & FILE_ATTRIBUTE_HIDDEN > 0
      @indexed       = @attr & ~FILE_ATTRIBUTE_NOT_CONTENT_INDEXED > 0
      @normal        = @attr & FILE_ATTRIBUTE_NORMAL > 0
      @offline       = @attr & FILE_ATTRIBUTE_OFFLINE > 0
      @readonly      = @attr & FILE_ATTRIBUTE_READONLY > 0
      @reparse_point = @attr & FILE_ATTRIBUTE_REPARSE_POINT > 0
      @sparse        = @attr & FILE_ATTRIBUTE_SPARSE_FILE > 0
      @system        = @attr & FILE_ATTRIBUTE_SYSTEM > 0
      @temporary     = @attr & FILE_ATTRIBUTE_TEMPORARY > 0

      @mode = get_mode

      if @reparse_point
        @symlink = get_symlink(path)
      else
        @symlink = false
      end
    ensure
      CloseHandle(handle) if handle
    end
  end

  ## Comparable

  # Compares two File::Stat objects using modification time.
  #--
  # Custom implementation necessary since we altered File::Stat.
  #
  def <=>(other)
    @mtime.to_i <=> other.mtime.to_i
  end

  ## Other

  # Returns whether or not the file is an archive file.
  #
  def archive?
    @archive
  end

  # Returns whether or not the file is a block device. For MS Windows a
  # block device is a removable drive, cdrom or ramdisk.
  #
  def blockdev?
    @blockdev
  end

  # Returns whether or not the file is a character device.
  #
  def chardev?
    @chardev
  end

  # Returns whether or not the file is compressed.
  #
  def compressed?
    @compressed
  end

  # Returns whether or not the file is a directory.
  #
  def directory?
    @directory
  end

  # Returns whether or not the file in encrypted.
  #
  def encrypted?
    @encrypted
  end

  # Returns whether or not the file is executable. Generally speaking, this
  # means .bat, .cmd, .com, and .exe files.
  #
  def executable?
    @executable
  end

  alias executable_real? executable?

  # Returns whether or not the file is a regular file, as opposed to a pipe,
  # socket, etc.
  #
  def file?
    @regular
  end

  # Returns the user ID of the file. If full_sid is true, then the full
  # string sid is returned instead.
  #--
  # The user id is the RID of the SID.
  def gid(full_sid = false)
    full_sid ? @grp_sid : @gid
  end

  def grpowned?
    @grpowned
  end

  # Returns whether or not the file is hidden.
  #
  def hidden?
    @hidden
  end

  # Returns whether or not the file is content indexed.
  #
  def indexed?
    @indexed
  end

  alias content_indexed? indexed?

  # Returns whether or not the file is 'normal'. This is only true if
  # virtually all other attributes are false.
  #
  def normal?
    @normal
  end

  # Returns whether or not the file is offline.
  #
  def offline?
    @offline
  end

  # Returns whether or not the current process owner is the owner of the file.
  #
  def owned?
    @owned
  end

  # Returns the drive number of the disk containing the file, or -1 if there
  # is no associated drive number.
  #
  def rdev
    fpath = File.expand_path(@path).wincode
    PathGetDriveNumber(fpath)
  end

  # Meaningless for MS Windows
  #
  def readable?
    @readable
  end

  # Meaningless for MS Windows
  #
  def readable_real?
    @readable_real
  end

  # Returns whether or not the file is readonly.
  #
  def readonly?
    @readonly
  end

  alias read_only? readonly?

  # Returns whether or not the file is a pipe.
  #
  def pipe?
    @pipe
  end

  alias socket? pipe?

  # Returns whether or not the file is a reparse point.
  #
  def reparse_point?
    @reparse_point
  end

  # Returns whether or not the file size is zero.
  #
  def size?
    @size > 0 ? @size : nil
  end

  # Returns whether or not the file is a sparse file. In most cases a sparse
  # file is an image file.
  #
  def sparse?
    @sparse
  end

  # Returns whether or not the file is a symlink.
  #
  def symlink?
    @symlink
  end

  # Returns whether or not the file is a system file.
  #
  def system?
    @system
  end

  # Returns whether or not the file is being used for temporary storage.
  #
  def temporary?
    @temporary
  end

  # Returns the user ID of the file. If full_sid is true, then the full
  # string sid is returned instead.
  #--
  # The user id is the RID of the SID.
  def uid(full_sid = false)
    full_sid ? @user_sid : @uid
  end

  # Meaningless on MS Windows.
  #
  def writable?
    @writable
  end

  # Meaningless on MS Windows.
  #
  def writable_real?
    @writable_real
  end

  # Returns whether or not the file size is zero.
  #
  def zero?
    @size == 0
  end

  # Identifies the type of file. The return string is one of 'file',
  # 'directory', 'characterSpecial', 'socket' or 'unknown'.
  #
  def ftype
    return 'directory' if @directory

    case @filetype
      when FILE_TYPE_CHAR
        'characterSpecial'
      when FILE_TYPE_DISK
        'file'
      when FILE_TYPE_PIPE
        'socket'
      else
        if blockdev?
          'blockSpecial'
        else
          'unknown'
        end
    end
  end

  # Returns a stringified version of a File::Stat object.
  #
  def inspect
    members = %w[
      archive? atime blksize blockdev? blocks compressed? ctime dev
      encrypted? gid hidden? indexed? ino mode mtime rdev nlink normal?
      offline? readonly? reparse_point? size sparse? system? temporary?
      uid
    ]

    str = "#<#{self.class}"

    members.sort.each{ |mem|
      if mem == 'mode'
        str << " #{mem}=" << sprintf("0%o", send(mem.intern))
      elsif mem[-1].chr == '?' # boolean methods
        str << " #{mem.chop}=" << send(mem.intern).to_s
      else
        str << " #{mem}=" << send(mem.intern).to_s
      end
    }

    str
  end

  # A custom pretty print method.  This was necessary not only to handle
  # the additional attributes, but to work around an error caused by the
  # builtin method for the current File::Stat class (see pp.rb).
  #
  def pretty_print(q)
    members = %w[
      archive? atime blksize blockdev? blocks compressed? ctime dev
      encrypted? gid hidden? indexed? ino mode mtime rdev nlink normal?
      offline? readonly? reparse_point? size sparse? system? temporary?
      uid
    ]

    q.object_group(self){
      q.breakable
      members.each{ |mem|
        q.group{
          q.text("#{mem}".ljust(15) + "=> ")
          if mem == 'mode'
            q.text(sprintf("0%o", send(mem.intern)))
          else
            val = self.send(mem.intern)
            if val.nil?
              q.text('nil')
            else
              q.text(val.to_s)
            end
          end
        }
        q.comma_breakable unless mem == members.last
      }
    }
  end

  private

  # This is based on fileattr_to_unixmode in win32.c
  def get_mode
    mode = 0

    s_iread = 0x0100; s_iwrite = 0x0080; s_iexec = 0x0040
    s_ifreg = 0x8000; s_ifdir = 0x4000; s_iwusr = 0200
    s_iwgrp = 0020; s_iwoth = 0002;

    if @readonly
      mode |= s_iread
    else
      mode |= s_iread | s_iwrite | s_iwusr
    end

    if @directory
      mode |= s_ifdir | s_iexec
    else
      mode |= s_ifreg
    end

    if @executable
      mode |= s_iexec
    end

    mode |= (mode & 0700) >> 3;
    mode |= (mode & 0700) >> 6;

    mode &= ~(s_iwgrp | s_iwoth)

    mode
  end

  # Returns whether or not +path+ is a block device.
  def get_blockdev(path)
    ptr = FFI::MemoryPointer.from_string(path.wincode)

    if PathStripToRoot(ptr)
      fpath = ptr.read_bytes(path.size * 2).split("\000\000").first
    else
      fpath = nil
    end

    case GetDriveType(fpath)
      when DRIVE_REMOVABLE, DRIVE_CDROM, DRIVE_RAMDISK
        true
      else
        false
    end
  end

  # Returns the blksize for +path+.
  #---
  # The jruby-ffi gem (as of 1.9.3) reports a failure here where it shouldn't.
  # Consequently, this method returns 4096 automatically for now on JRuby.
  #
  def get_blksize(path)
    return 4096 if RUBY_PLATFORM == 'java' # Bug in jruby-ffi

    ptr = FFI::MemoryPointer.from_string(path.wincode)

    if PathStripToRoot(ptr)
      fpath = ptr.read_bytes(path.size * 2).split("\000\000").first
    else
      fpath = nil
    end

    size = nil

    sectors = FFI::MemoryPointer.new(:ulong)
    bytes   = FFI::MemoryPointer.new(:ulong)
    free    = FFI::MemoryPointer.new(:ulong)
    total   = FFI::MemoryPointer.new(:ulong)

    if GetDiskFreeSpace(fpath, sectors, bytes, free, total)
      size = sectors.read_ulong * bytes.read_ulong
    else
      unless PathIsUNC(fpath)
        raise SystemCallError.new('GetDiskFreeSpace', FFI.errno)
      end
    end

    size
  end

  # Generic method for retrieving a handle.
  def get_handle(path)
    fpath = path.wincode

    handle = CreateFile(
      fpath,
      GENERIC_READ,
      FILE_SHARE_READ,
      nil,
      OPEN_EXISTING,
      FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OPEN_REPARSE_POINT,
      0
    )

    if handle == INVALID_HANDLE_VALUE
      return nil if FFI.errno == 32 # ERROR_SHARING_VIOLATION. Locked files.
      raise SystemCallError.new('CreateFile', FFI.errno)
    end

    handle
  end

  # Determines whether or not +file+ is a symlink.
  def get_symlink(file)
    bool = false
    fpath = File.expand_path(file).wincode

    begin
      data = WIN32_FIND_DATA.new
      handle = FindFirstFile(fpath, data)

      if handle == INVALID_HANDLE_VALUE
        raise SystemCallError.new('FindFirstFile', FFI.errno)
      end

      if data[:dwReserved0] == IO_REPARSE_TAG_SYMLINK
        bool = true
      end
    ensure
      FindClose(handle) if handle
    end

    bool
  end

  # Returns the filetype for the given +handle+.
  def get_filetype(handle)
    file_type = GetFileType(handle)

    if file_type == FILE_TYPE_UNKNOWN && FFI.errno != NO_ERROR
      raise SystemCallError.new('GetFileType', FFI.errno)
    end

    file_type
  end

  # Return a sid of the file's owner.
  def get_file_sid(file, info)
    wfile = file.wincode
    size_needed_ptr = FFI::MemoryPointer.new(:ulong)

    # First pass, get the size needed
    bool = GetFileSecurity(wfile, info, nil, 0, size_needed_ptr)

    size_needed  = size_needed_ptr.read_ulong
    security_ptr = FFI::MemoryPointer.new(size_needed)

    # Second pass, this time with the appropriately sized security pointer
    bool = GetFileSecurity(wfile, info, security_ptr, security_ptr.size, size_needed_ptr)

    unless bool
      error = FFI.errno
      return "S-1-5-80-0" if error == 32 # ERROR_SHARING_VIOLATION. Locked files, etc.
      raise SystemCallError.new("GetFileSecurity", error)
    end

    sid_ptr   = FFI::MemoryPointer.new(:pointer)
    defaulted = FFI::MemoryPointer.new(:bool)

    if info == OWNER_SECURITY_INFORMATION
      bool = GetSecurityDescriptorOwner(security_ptr, sid_ptr, defaulted)
      meth = "GetSecurityDescriptorOwner"
    else
      bool = GetSecurityDescriptorGroup(security_ptr, sid_ptr, defaulted)
      meth = "GetSecurityDescriptorGroup"
    end

    raise SystemCallError.new(meth, FFI.errno) unless bool

    ptr = FFI::MemoryPointer.new(:string)

    unless ConvertSidToStringSid(sid_ptr.read_pointer, ptr)
      raise SystemCallError.new("ConvertSidToStringSid")
    end

    ptr.read_pointer.read_string
  end

  # Return the sid of the current process.
  def get_current_process_sid(token_type)
    token = FFI::MemoryPointer.new(:uintptr_t)
    sid = nil

    begin
      # Get the current process sid
      unless OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, token)
        raise SystemCallError.new("OpenProcessToken", FFI.errno)
      end

      token   = token.read_pointer.to_i
      rlength = FFI::MemoryPointer.new(:pointer)

      if token_type == TokenUser
        buf = 0.chr * 512
      else
        buf = TOKEN_GROUP.new
      end

      unless GetTokenInformation(token, token_type, buf, buf.size, rlength)
        raise SystemCallError.new("GetTokenInformation", FFI.errno)
      end

      if token_type == TokenUser
        tsid = buf[FFI.type_size(:pointer)*2, (rlength.read_ulong - FFI.type_size(:pointer)*2)]
      else
        tsid = buf[:Groups][0][:Sid]
      end

      ptr = FFI::MemoryPointer.new(:string)

      unless ConvertSidToStringSid(tsid, ptr)
        raise SystemCallError.new("ConvertSidToStringSid")
      end

      sid = ptr.read_pointer.read_string
    ensure
      CloseHandle(token) if token
    end

    sid
  end
end

if $0 == __FILE__
  p File::Stat.new("C:/Users/djberge/test.txt").ino
  #p File::Stat.new("C:/Users/djberge/test.txt").gid
  #p File::Stat.new("C:/Users/djberge/test.txt").gid(true)
  #p File::Stat.new("C:/Users/djberge/test.txt").grpowned?

  #p File::Stat.new("E:/")
  #p File::Stat.new("E:/").gid
  #p File::Stat.new("E:/").gid(true)

  #File::Stat.new(Dir.pwd)
  #p File::Stat.new(Dir.pwd).uid
  #p File::Stat.new("C:/").uid(true)
  #p File::Stat.new("C:/pagefile.sys").uid
end
