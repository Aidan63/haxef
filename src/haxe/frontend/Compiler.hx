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

	public function help(cb:Callback<NoData>) {
		Process.open(path.add('haxe.exe'), { env: [ 'HAXE_STD_PATH' => path.add('std') ], args: [ '-p', 'D:\\programming\\haxe\\haxe-frontend\\test', '--run', 'Test' ] }, (proc, error) -> {
			switch error {
				case null:
					proc.exitCode((code, error) -> {
						trace(code, error);
					});
				case exn:
					cb.fail(exn);
			}
		});
	}
}