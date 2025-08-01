package haxeLanguageServer.features.hxml;

import haxeLanguageServer.features.hxml.data.Defines;
import haxeLanguageServer.features.hxml.data.Flags;
import haxeLanguageServer.features.hxml.data.Shared;
import js.lib.Promise;

using Lambda;

typedef HxmlContext = {
	final element:HxmlElement;
	final range:Range;
}

enum HxmlElement {
	Flag(?flag:Flag);
	EnumValue(?value:EnumValue, values:EnumValues);
	Define(?define:Define);
	DefineValue(?define:Define, value:String);
	File(?path:String);
	Directory(?path:String);
	LibraryName(?name:String);
	Unknown;
}

function analyzeHxmlContext(line:String, pos:Position):js.lib.Promise<HxmlContext> {
	final range = findWordRange(line, pos.character);
	line = line.substring(0, range.end);
	final parts = ~/\s+/.replace(line.ltrim(), " ").split(" ");
	function findFlag(word) {
		return HxmlFlags.flatten().find(f -> f.name == word || f.shortName == word || f.deprecatedNames?.contains(word));
	}
	var range = {
		start: {line: pos.line, character: range.start},
		end: {line: pos.line, character: range.end}
	};
	return switch parts {
		case []:
			Promise.resolve({element: Flag(), range: range});
		case [flag]:
			Promise.resolve({element: Flag(findFlag(flag)), range: range});
		case [flag, arg]:
			final flag = findFlag(flag);
			switch flag?.argument?.kind {
				case null:
					Promise.resolve({element: Unknown, range: range});
				case Enum(values):
					Promise.resolve({element: EnumValue(values.find(v -> v.name == arg), values), range: range});
				case Define:
					getDefines(true).then(function(defines) {
						function findDefine(define) {
							return defines.find(d -> d.matches(define));
						}
						var elt = switch arg.split("=") {
							case []:
								Define();
							case [define]:
								Define(findDefine(define));
							case [define, value]:
								final define = findDefine(define);
								final enumValues = define?.getEnumValues();
								if (enumValues != null) {
									EnumValue(enumValues.find(v -> v.name == arg), enumValues);
								} else {
									DefineValue(define, value);
								}
							case _:
								Unknown;
						}
						return {element: elt, range: range};
					});
				case File:
					Promise.resolve({element: File(arg), range: range});
				case Directory:
					Promise.resolve({element: Directory(arg), range: range});
				case LibraryName:
					Promise.resolve({element: LibraryName(arg), range: range});
			}
		case _:
			Promise.resolve({element: Unknown, range: range}); // no completion after the first argument
	}
}

private function findWordRange(s:String, index:Int) {
	function isWordBoundary(c:String):Bool {
		return c.isSpace(0) || c == "=" || c == ":";
	}
	var start = 0;
	var end = 0;
	var inWord = false;
	for (i in 0...s.length) {
		final c = s.charAt(i);
		if (isWordBoundary(c)) {
			if (inWord) {
				inWord = false;
				end = i;
				if (start <= index && end >= index) {
					// "Te|xt"
					return {start: start, end: end};
				}
			}
		} else {
			if (!inWord) {
				inWord = true;
				start = i;
			}
		}
	}
	// "Text|"
	if (inWord) {
		return {start: start, end: s.length};
	}
	// "Text |"
	return {start: index, end: index};
}
