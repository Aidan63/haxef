package haxe.frontend;

import haxe.frontend.parsers.Version;
import asys.native.filesystem.FilePath;

class Dependency {
    public final name:String;

    public final version:Version;

    /**
     * Absolute path to the library folder.
     */
    public final directory:FilePath;

    /**
     * Absolute path to the folder containing the library source files.
     * If `path` does not contain a `haxelib.json` file with `classPath` defined this is the same as `path`.
     */
    public final classPath:FilePath;

    public final dependencies:Array<Dependency>;

    public final extraArguments:Array<String>;

	public function new(name, version, directory, classPath, dependencies, extraArguments) {
        this.name           = name;
		this.directory      = directory;
		this.version        = version;
        this.classPath      = classPath;
		this.dependencies   = dependencies;
        this.extraArguments = extraArguments;
	}
}