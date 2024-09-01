import haxe.fontend.Container;

class Main {
	static function main() {
		Container.populate(Sys.getCwd(), null, (container, error) -> {
			switch error {
				case null:
					container.resolve('foo', (dependency, error) -> {
						switch error {
							case null:
								trace(dependency);
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
