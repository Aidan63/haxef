import haxe.frontend.Container;
import haxe.frontend.Dependency;
import sys.io.File;
import hxml.Hxml;

class Main {

	// static function main() {
	// 	final str  = File.getContent('D:/programming/haxe/haxe-frontend/build.hxml');
	// 	final hxml = Hxml.parse('-p src -D foo -D bar=baz --main Main --cpp bin --debug');

	// 	trace(hxml.sets);

	// 	// final hxml = new Hxml('-D foo -D foo=bar -D "foo"=bar -D foo="bar" -D "foo"="bar"');
	// }

	static function print(d:Dependency, indent:String) {
		trace('${indent}${d.classPath} ${d.version}');

		for (dep in d.dependencies) {
			print(dep, indent + '    ');
		}
	}

	static function main() {
		Container.populate(Sys.getCwd(), null, (container, error) -> {
			switch error {
				case null:
					// container.resolve('foo', (dependency, error) -> {
					// 	switch error {
					// 		case null:
					// 			print(dependency, '');
					// 		case exn:
					// 			throw exn;
					// 	}
					// });

					// container.haxec((compiler, error) -> {
					// 	switch error {
					// 		case null:
					// 			compiler.help((d, error) -> {
					// 				trace(d);
					// 				trace(error);
					// 			});
					// 		case exn:
					// 			throw exn;
					// 	}
					// });

					container.compile([ '-p', 'src', '-D', 'test', '-L', 'foo' ], (_, error) -> {
						switch error {
							case null:
								trace('done');
							case exn:
								trace(exn);
						}
					});
				case exn:
					throw exn;
			}
		});
	}
}
