package haxe.frontend;

import haxe.parsers.Version;

class Haxelib {
    @:jcustomparse(haxe.frontend.LockFile.Library.parseVersion)
    public var version:Version;

    public var classPath:String;

    public var depdendencies:Map<String, String>;
}