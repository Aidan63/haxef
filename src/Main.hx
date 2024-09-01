import haxe.frontend.Dependency;
import haxe.parsers.Version;
import haxe.frontend.Container;

class Main {
	static function print(d:Dependency, indent:String) {
		trace('${indent}${d.path} ${d.version}');

		for (dep in d.dependencies) {
			print(dep, indent + '    ');
		}
	}

	static function main() {
		Container.populate(Sys.getCwd(), null, (container, error) -> {
			switch error {
				case null:
					container.resolve('foo', (dependency, error) -> {
						switch error {
							case null:
								print(dependency, '');
							case exn:
								throw exn;
						}
					});
				case exn:
					throw exn;
			}
		});
	}
}
