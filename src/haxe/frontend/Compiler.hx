package haxe.frontend;

import haxe.io.Path;
import asys.native.system.Process;
import asys.native.filesystem.FilePath;
import haxe.ds.Option;
import haxe.parsers.Version;

class Compiler {
    public final version : Option<Version>;

    public final path:FilePath;

	public function new(version:Option<Version>, path:FilePath) {
		this.version = version;
		this.path    = path;
	}
}