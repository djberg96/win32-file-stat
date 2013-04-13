module Windows
  module Constants
    MAX_PATH = 260
    MAXDWORD = 0xFFFFFFFF

    INVALID_HANDLE_VALUE = 0xFFFFFFFF

    ERROR_FILE_NOT_FOUND = 2
    ERROR_NO_MORE_FILES  = 18

    FILE_TYPE_UNKNOWN = 0x0000
    FILE_TYPE_DISK    = 0x0001
    FILE_TYPE_CHAR    = 0x0002
    FILE_TYPE_PIPE    = 0x0003
    FILE_TYPE_REMOTE  = 0x8000

    FILE_ATTRIBUTE_READONLY      = 0x00000001
    FILE_ATTRIBUTE_HIDDEN        = 0x00000002
    FILE_ATTRIBUTE_SYSTEM        = 0x00000004
    FILE_ATTRIBUTE_DIRECTORY     = 0x00000010
    FILE_ATTRIBUTE_ARCHIVE       = 0x00000020
    FILE_ATTRIBUTE_ENCRYPTED     = 0x00000040
    FILE_ATTRIBUTE_NORMAL        = 0x00000080
    FILE_ATTRIBUTE_TEMPORARY     = 0x00000100
    FILE_ATTRIBUTE_SPARSE_FILE   = 0x00000200
    FILE_ATTRIBUTE_REPARSE_POINT = 0x00000400
    FILE_ATTRIBUTE_COMPRESSED    = 0x00000800
    FILE_ATTRIBUTE_OFFLINE       = 0x00001000

    FILE_ATTRIBUTE_NOT_CONTENT_INDEXED = 0x00002000

    DRIVE_REMOVABLE   = 2
    DRIVE_CDROM       = 5
    DRIVE_RAMDISK     = 6

    NO_ERROR = 0

    OPEN_EXISTING   = 3
    GENERIC_READ    = 0x80000000
    FILE_SHARE_READ = 1

    FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
  end
end
