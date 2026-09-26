// Spotlight's calculator and unit converter, like on a Mac: "12*(3+4)", "2^10", "√2",
// "15% von 80", "5 km in m", "100 °C in °F", "3 zoll in cm". A small parser of its own –
// never eval(): what is typed is never run as code. German number style both ways
// ("3,5" in, "1.234,5" out).
.pragma library

// ---------------------------------------------------------------- expressions

const FUNCTIONS = {
    sqrt: Math.sqrt, wurzel: Math.sqrt, sin: x => Math.sin(x), cos: x => Math.cos(x), tan: x => Math.tan(x),
    ln: Math.log, log: Math.log10, lg: Math.log10, abs: Math.abs, round: Math.round, rund: Math.round,
    floor: Math.floor, ceil: Math.ceil, exp: Math.exp
};
const CONSTANTS = { pi: Math.PI, "π": Math.PI, e: Math.E };

function tokenize(text) {
    const tokens = [];
    const s = text.replace(/×/g, "*").replace(/÷/g, "/").replace(/−/g, "-").replace(/√/g, " sqrt ");
    let i = 0;
    while (i < s.length) {
        const c = s[i];
        if (/\s/.test(c)) { i++; continue; }
        const num = s.slice(i).match(/^(\d+(?:[.,]\d+)?|[.,]\d+)/);
        if (num) {
            tokens.push({ t: "num", v: parseFloat(num[1].replace(",", ".")) });
            i += num[1].length;
            continue;
        }
        const word = s.slice(i).match(/^[a-zA-Zπ]+/);
        if (word) {
            const w = word[0].toLowerCase();
            if (FUNCTIONS[w]) tokens.push({ t: "fn", v: FUNCTIONS[w] });
            else if (CONSTANTS[w] !== undefined) tokens.push({ t: "num", v: CONSTANTS[w] });
            else return null;
            i += word[0].length;
            continue;
        }
        if ("+-*/^()%!".includes(c)) { tokens.push({ t: "op", v: c }); i++; continue; }
        return null;
    }
    return tokens;
}

// expr := term (("+"|"-") term)*   term := factor (("*"|"/"|implicit) factor)*
// factor := unary ("^" factor)?    unary := "-" unary | postfix   postfix := primary ("%"|"!")*
function parse(tokens) {
    let pos = 0;
    const peek = () => tokens[pos];
    const isOp = v => peek() && peek().t === "op" && peek().v === v;
    function expr() {
        let v = term();
        while (isOp("+") || isOp("-")) {
            const op = tokens[pos++].v;
            const r = term();
            v = op === "+" ? v + r : v - r;
        }
        return v;
    }
    function term() {
        let v = factor();
        for (;;) {
            if (isOp("*") || isOp("/")) {
                const op = tokens[pos++].v;
                const r = factor();
                v = op === "*" ? v * r : v / r;
            } else if (peek() && (peek().t === "num" || peek().t === "fn" || isOp("("))) {
                v = v * factor(); // 2π, 3(4+1)
            } else {
                return v;
            }
        }
    }
    function factor() {
        const base = unary();
        if (isOp("^")) {
            pos++;
            return Math.pow(base, factor());
        }
        return base;
    }
    function unary() {
        if (isOp("-")) { pos++; return -unary(); }
        if (isOp("+")) { pos++; return unary(); }
        return postfix();
    }
    function postfix() {
        let v = primary();
        while (isOp("%") || isOp("!")) {
            const op = tokens[pos++].v;
            if (op === "%") v = v / 100;
            else {
                if (v < 0 || v > 170 || v !== Math.floor(v)) throw "factorial";
                let f = 1;
                for (let k = 2; k <= v; k++) f *= k;
                v = f;
            }
        }
        return v;
    }
    function primary() {
        const tok = tokens[pos++];
        if (!tok) throw "end";
        if (tok.t === "num") return tok.v;
        if (tok.t === "fn") return tok.v(isOp("(") ? primary() : factor());
        if (tok.t === "op" && tok.v === "(") {
            const v = expr();
            if (!isOp(")")) throw "paren";
            pos++;
            return v;
        }
        throw "unexpected";
    }
    const v = expr();
    if (pos !== tokens.length) throw "rest";
    return v;
}

function format(v, digits) {
    if (!isFinite(v)) return null;
    const rounded = Math.abs(v) >= 1e15 || (Math.abs(v) < 1e-6 && v !== 0) ? v.toExponential(6) : String(+v.toPrecision(digits ?? 12));
    // German style: 1.234.567,89
    if (rounded.includes("e")) return rounded.replace(".", ",");
    const [int, frac] = rounded.split(".");
    const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ".");
    return frac ? grouped + "," + frac : grouped;
}

// "15% von 80" → 12
function percentOf(text) {
    const m = text.match(/^\s*([\d.,]+)\s*%\s*(?:von|of)\s*([\d.,]+)\s*$/i);
    return m ? parseFloat(m[1].replace(",", ".")) / 100 * parseFloat(m[2].replace(",", ".")) : null;
}

// { value, text } of a calculation, or null when the text is none (a lone number is none)
function evaluate(text) {
    const t = text.trim().replace(/=\s*$/, "");
    if (t === "") return null;
    const p = percentOf(t);
    if (p !== null) return { value: p, text: format(p) };
    if (!/[+\-*/^%!×÷√()]|\b(sqrt|wurzel|sin|cos|tan|ln|log|lg|abs|pi|exp)\b|π/i.test(t)) return null;
    const tokens = tokenize(t);
    if (!tokens || tokens.length < 2) return null;
    try {
        const v = parse(tokens);
        const f = format(v);
        return f === null ? null : { value: v, text: f };
    } catch (e) {
        return null;
    }
}

// ---------------------------------------------------------------- units

// factor to the base unit of its kind (temperature: special)
const UNITS = {
    length: { m: 1, meter: 1, km: 1000, kilometer: 1000, cm: 0.01, zentimeter: 0.01, mm: 0.001, millimeter: 0.001,
        µm: 1e-6, nm: 1e-9, mi: 1609.344, meile: 1609.344, meilen: 1609.344, mile: 1609.344, miles: 1609.344,
        yd: 0.9144, yard: 0.9144, ft: 0.3048, fuß: 0.3048, fuss: 0.3048, feet: 0.3048, foot: 0.3048,
        in: 0.0254, zoll: 0.0254, inch: 0.0254, sm: 1852, seemeile: 1852 },
    mass: { kg: 1, kilogramm: 1, g: 0.001, gramm: 0.001, mg: 1e-6, t: 1000, tonne: 1000, tonnen: 1000,
        lb: 0.45359237, lbs: 0.45359237, pfund: 0.5, oz: 0.028349523, unze: 0.028349523, st: 6.35029318 },
    volume: { l: 1, liter: 1, ml: 0.001, milliliter: 0.001, cl: 0.01, dl: 0.1, m3: 1000, "m³": 1000, cm3: 0.001,
        "cm³": 0.001, gal: 3.785411784, gallone: 3.785411784, gallon: 3.785411784, qt: 0.946352946, pt: 0.473176473,
        cup: 0.2365882365, tasse: 0.25, floz: 0.0295735296 },
    area: { m2: 1, "m²": 1, km2: 1e6, "km²": 1e6, cm2: 1e-4, "cm²": 1e-4, ha: 1e4, hektar: 1e4, a: 100, ar: 100,
        acre: 4046.8564224, sqft: 0.09290304 },
    time: { s: 1, sek: 1, sekunde: 1, sekunden: 1, sec: 1, ms: 0.001, min: 60, minute: 60, minuten: 60, h: 3600,
        std: 3600, stunde: 3600, stunden: 3600, tag: 86400, tage: 86400, d: 86400, woche: 604800, wochen: 604800,
        jahr: 31557600, jahre: 31557600 },
    speed: { "m/s": 1, "km/h": 1 / 3.6, kmh: 1 / 3.6, mph: 0.44704, kn: 0.514444, knoten: 0.514444 },
    data: { b: 1, byte: 1, bytes: 1, kb: 1e3, mb: 1e6, gb: 1e9, tb: 1e12, kib: 1024, mib: 1048576, gib: 1073741824,
        tib: 1099511627776, bit: 0.125, kbit: 125, mbit: 125000, gbit: 1.25e8 },
    energy: { j: 1, joule: 1, kj: 1000, kcal: 4184, cal: 4.184, kwh: 3.6e6, wh: 3600 }
};
const TEMPERATURE = { c: "c", "°c": "c", celsius: "c", f: "f", "°f": "f", fahrenheit: "f", k: "k", kelvin: "k" };
const LABEL = { c: "°C", f: "°F", k: "K" };

function kindOf(unit) {
    for (const kind in UNITS)
        if (UNITS[kind][unit] !== undefined)
            return kind;
    return null;
}

function toCelsius(v, u) {
    return u === "c" ? v : u === "f" ? (v - 32) * 5 / 9 : v - 273.15;
}
function fromCelsius(v, u) {
    return u === "c" ? v : u === "f" ? v * 9 / 5 + 32 : v + 273.15;
}

// "5 km in m" → { value, text: "5.000 m" }, or null
function convert(text) {
    const m = text.trim().match(/^(-?[\d.,]+)\s*([^\s\d]+?)\s+(?:in|nach|zu|to|=)\s+([^\s\d]+)$/i);
    if (!m) return null;
    const value = parseFloat(m[1].replace(/\.(?=\d{3}\b)/g, "").replace(",", "."));
    const from = m[2].toLowerCase(), to = m[3].toLowerCase();
    if (!isFinite(value)) return null;
    if (TEMPERATURE[from] && TEMPERATURE[to]) {
        const v = fromCelsius(toCelsius(value, TEMPERATURE[from]), TEMPERATURE[to]);
        return { value: v, text: format(v, 6) + " " + LABEL[TEMPERATURE[to]] };
    }
    const kind = kindOf(from);
    if (!kind || kindOf(to) !== kind) return null;
    const v = value * UNITS[kind][from] / UNITS[kind][to];
    return { value: v, text: format(v, 6) + " " + m[3] };
}
