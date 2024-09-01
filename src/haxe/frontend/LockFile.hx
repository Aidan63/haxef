package haxe.frontend;

import asys.native.filesystem.FilePath;
import haxe.parsers.Version;

typedef LockFile = Map<String, Library>;

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
                Version.fromString(s);
            case _:
                throw new Exception('Failed to parse file path');
        }
    }
}