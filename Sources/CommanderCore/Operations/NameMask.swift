import Foundation

/// Windows-style target name mask ("*.*", "*.bak", "new_*.*", "???_x.*").
/// The mask and the name are split at their last dot (a leading dot does not
/// start an extension). In each part `*` takes the rest of the original part,
/// `?` takes one character of it, anything else is literal. An empty rendered
/// extension drops the dot.
public enum NameMask {
    public static func apply(_ mask: String, to name: String) -> String {
        let mask = mask.trimmingCharacters(in: .whitespaces)
        if mask.isEmpty || mask == "*.*" || mask == "*" { return name }
        guard let dot = mask.lastIndex(of: ".") else {
            return render(Array(mask), Array(name))
        }
        let (base, ext) = split(name)
        let renderedBase = render(Array(mask[..<dot]), Array(base))
        let renderedExt = render(Array(mask[mask.index(after: dot)...]), Array(ext))
        return renderedExt.isEmpty ? renderedBase : renderedBase + "." + renderedExt
    }

    static func split(_ name: String) -> (base: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    private static func render(_ mask: [Character], _ source: [Character]) -> String {
        var out = ""
        var i = 0
        for c in mask {
            switch c {
            case "*":
                if i < source.count { out.append(contentsOf: source[i...]) }
                i = source.count
            case "?":
                if i < source.count {
                    out.append(source[i])
                    i += 1
                }
            default:
                out.append(c)
            }
        }
        return out
    }
}
