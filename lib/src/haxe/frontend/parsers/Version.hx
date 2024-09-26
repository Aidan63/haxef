package haxe.frontend.parsers;

import hxparse.ParserBuilder;
import byte.ByteData;
import hxparse.LexerTokenSource;
import hxparse.Parser;
import hxparse.RuleBuilder;
import hxparse.Lexer;

private enum Preview {
    Alpha;
    Beta;
    Rc;
}

private enum Tokens {
    TNumber(i:Int);
    TDot;
    TDash;
    TPreview(preview:Preview);
    TEof;
}

private class VersionLexer extends Lexer implements RuleBuilder {
    public static var tok = @:rule [
        '\\.' => TDot,
        '\\-' => TDash,
        'alpha' => TPreview(Alpha),
        'beta' => TPreview(Beta),
        'rc' => TPreview(Rc),
        '[1-9][0-9]*|0' => TNumber(Std.parseInt(lexer.current)),
        "[\r\n\t ]" => lexer.token(tok),
        '' => TEof
    ];
}

private class VersionData {
    public final major:Int;

    public final minor:Int;

    public final patch:Int;

    public final preview:Null<Preview>;

    public final release:Null<Int>;

	public function new(major:Int, minor:Int, patch:Int, preview:Null<Preview>, release:Null<Int>) {
		this.major   = major;
		this.minor   = minor;
		this.patch   = patch;
		this.preview = preview;
		this.release = release;
	}
}

private class VersionParser extends Parser<LexerTokenSource<Tokens>, Tokens> implements ParserBuilder {
    public function new(input:String) {
        super(
            new LexerTokenSource(
                new VersionLexer(ByteData.ofString(input)),
                VersionLexer.tok));
    }

    public function create():VersionData {
        return switch stream {
            case [ TNumber(major), TDot, TNumber(minor), TDot, TNumber(patch) ]:
                switch stream {
                    case [ TEof ]:
                        new VersionData(major, minor, patch, null, null);
                    case [ TDash, TPreview(preview) ]:
                        switch stream {
                            case [ TEof ]:
                                new VersionData(major, minor, patch, preview, null);
                            case [ TNumber(release), TEof ]:
                                new VersionData(major, minor, patch, preview, release);
                        };
                };
        };
    }
}

@:forward abstract Version(VersionData) {
    function new(data) {
        this = data;
    }

    @:from public static function fromString(version:String):Version {
        return new Version(new VersionParser(version).create());
    }

    @:to public function toString() {
        final buffer = new StringBuf();
        buffer.add('${this.major}.${this.minor}.${this.patch}');
        
        if (this.preview != null) {
            buffer.add('-${this.preview}');
        }
        if (this.release != null) {
            buffer.add('.${this.release}');
        }

        return buffer.toString();
    }
}