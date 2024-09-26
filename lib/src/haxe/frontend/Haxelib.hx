package haxe.frontend;

import asys.native.filesystem.FilePath;
import haxe.frontend.parsers.Version;

class Haxelib {
    @:jcustomparse(haxe.frontend.LockFile.Library.parseVersion)
    public var version:Version;

    @:jcustomparse(haxe.frontend.LockFile.Library.parsePath)
    public var classPath:FilePath;

    @:default(new Map<String, String>())
    public var dependencies:Map<String, String>;
}