import haxe.frontend.Container;

class Main {
	static function main() {
		Container.populate(Sys.getCwd(), null, (container, error) -> {
			switch error {
				case null:
					container.resolve('baz', (dependency, error) -> {
						switch error {
							case null:
								trace(dependency.path);
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
