import haxe.parsers.Version;
import haxe.frontend.Container;

class Main {
	static function main() {
		Container.populate(Sys.getCwd(), null, (container, error) -> {
			switch error {
				case null:
					container.resolve('foo', (dependency, error) -> {
						switch error {
							case null:
								trace(dependency.path, dependency.version, dependency.dependencies);
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
