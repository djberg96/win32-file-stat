require File.join(File.dirname(__FILE__), 'constants')

require 'ffi'

module Windows
  module Structs
    extend FFI::Library

    class LowHigh < FFI::Struct
      layout(:LowPart, :ulong, :HighPart, :ulong)
    end

    class ULARGE_INTEGER < FFI::Union
      layout(:u, LowHigh, :QuadPart, :ulong_long)
    end

    class FILETIME < FFI::Struct
      layout(:dwLowDateTime, :ulong, :dwHighDateTime, :ulong)
    end

    class BY_HANDLE_FILE_INFORMATION < FFI::Struct
      include Windows::Constants

      layout(
        :dwFileAttributes, :ulong,
        :ftCreationTime, FILETIME,
        :ftLastAccessTime, FILETIME,
        :ftLastWriteTime, FILETIME,
        :dwVolumeSerialNumber, :ulong,
        :nFileSizeHigh, :ulong,
        :nFileSizeLow, :ulong,
        :nNumberOfLinks, :ulong,
        :nFileIndexHigh, :ulong,
        :nFileIndexLow, :ulong
      )

      # Return the atime as a number
      def atime
        date = ULARGE_INTEGER.new
        date[:u][:LowPart] = self[:ftLastAccessTime][:dwLowDateTime]
        date[:u][:HighPart] = self[:ftLastAccessTime][:dwHighDateTime]
        date[:QuadPart] / 10000000 - 11644473600 # ns, 100-ns since Jan 1, 1601.
      end

      # Return the ctime as a number
      def ctime
        date = ULARGE_INTEGER.new
        date[:u][:LowPart] = self[:ftCreationTime][:dwLowDateTime]
        date[:u][:HighPart] = self[:ftCreationTime][:dwHighDateTime]
        date[:QuadPart] / 10000000 - 11644473600 # ns, 100-ns since Jan 1, 1601.
      end

      # Return the mtime as a number
      def mtime
        date = ULARGE_INTEGER.new
        date[:u][:LowPart] = self[:ftLastWriteTime][:dwLowDateTime]
        date[:u][:HighPart] = self[:ftLastWriteTime][:dwHighDateTime]
        date[:QuadPart] / 10000000 - 11644473600 # ns, 100-ns since Jan 1, 1601.
      end

      # Return the size as a single number
      def size
        (self[:nFileSizeHigh] * (MAXDWORD + 1)) + self[:nFileSizeLow]
      end
    end

    class WIN32_FIND_DATA < FFI::Struct
      include Windows::Constants

      layout(
        :dwFileAttributes, :ulong,
        :ftCreationTime, FILETIME,
        :ftLastAccessTime, FILETIME,
        :ftLastWriteTime, FILETIME,
        :nFileSizeHigh, :ulong,
        :nFileSizeLow, :ulong,
        :dwReserved0, :ulong,
        :dwReserved1, :ulong,
        :cFileName, [:uint8, MAX_PATH*2],
        :cAlternateFileName, [:uint8, 28]
      )

      # Return the atime as a number
      def atime
        date = ULARGE_INTEGER.new
        date[:u][:LowPart] = self[:ftLastAccessTime][:dwLowDateTime]
        date[:u][:HighPart] = self[:ftLastAccessTime][:dwHighDateTime]
        return 0 if date[:QuadPart]==0
        date[:QuadPart] / 10000000 - 11644473600 # ns, 100-ns since Jan 1, 1601.
      end

      # Return the ctime as a number
      def ctime
        date = ULARGE_INTEGER.new
        date[:u][:LowPart] = self[:ftCreationTime][:dwLowDateTime]
        date[:u][:HighPart] = self[:ftCreationTime][:dwHighDateTime]
        return 0 if date[:QuadPart]==0
        date[:QuadPart] / 10000000 - 11644473600 # ns, 100-ns since Jan 1, 1601.
      end

      # Return the mtime as a number
      def mtime
        date = ULARGE_INTEGER.new
        date[:u][:LowPart] = self[:ftLastWriteTime][:dwLowDateTime]
        date[:u][:HighPart] = self[:ftLastWriteTime][:dwHighDateTime]
        return 0 if date[:QuadPart]==0
        date[:QuadPart] / 10000000 - 11644473600 # ns, 100-ns since Jan 1, 1601.
      end

      # Return the size as a single number
      def size
        (self[:nFileSizeHigh] * (MAXDWORD + 1)) + self[:nFileSizeLow]
      end
    end

    class SID_AND_ATTRIBUTES < FFI::Struct
      layout(:Sid, :pointer, :Attributes, :ulong)
    end

    class TOKEN_GROUP < FFI::Struct
      layout(
        :GroupCount, :ulong,
        :Groups, [SID_AND_ATTRIBUTES, 128]
      )
    end
  end
end
