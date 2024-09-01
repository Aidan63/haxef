package haxe.frontend;

import asys.native.filesystem.FilePath;

typedef LockFile = Map<String, Library>;

class Version {
    public final major : Int;

    public final minor : Int;

    public final patch : Int;

    public function new(major, minor, patch) {
        this.major = major;
        this.minor = minor;
        this.patch = patch;
    }
}

class Library {
    @:jcustomparse(haxe.frontend.LockFile.Library.parseVersion)
    public var version : Version;

    @:jcustomparse(haxe.frontend.LockFile.Library.parsePath)
    public var path : FilePath;

    @:default(new Array<String>())
    public var dependencies : Array<String>;

    public static function parsePath(val:hxjsonast.Json, name:String) {
        return switch val.value {
            case JString(s):
                return FilePath.ofString(s);
            case _:
                throw new Exception('Failed to parse file path');
        }
    }

    public static function parseVersion(val:hxjsonast.Json, name:String) {
        return switch val.value {
            case JString(s):
                return new Version(1, 0, 0);
            case _:
                throw new Exception('Failed to parse file path');
        }
    }
}