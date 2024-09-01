package haxe.frontend;

import haxe.parsers.Version;
import asys.native.filesystem.FilePath;

class Dependency {
    public final path:FilePath;

    public final version:Version;

    public final dependencies:Array<Dependency>;

    public final extraArguments:String;

	public function new(path, version, dependencies, extraArguments) {
		this.path           = path;
		this.version        = version;
		this.dependencies   = dependencies;
        this.extraArguments = extraArguments;
	}
}