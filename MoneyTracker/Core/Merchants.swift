import Foundation

// Shared merchant prior — a line-for-line port of the web app's lib/merchants.js.
// Day-one categories for well-known (mostly DE/EU) shops, so REWE reads as Groceries and
// Netflix as Subscriptions from the first sync, for anyone, offline.
// PRIVACY: only ORGANISATIONS appear here — never a personal name. Brand tokens that are
// also common names (Norma, Penny, Douglas, Bolt, Tier, Bird) need retail context.
// Precedence (most specific wins): your decision > what you taught for this payee > this
// list > the bank's guess. It only fills a category that would otherwise be "Other".
enum Merchants {
    private static let retailCtx = JSRegex.make(#"(sagt danke|danke|markt|filiale|gmbh|\bag\b|\bse\b|\bkg\b|discount|supermarkt|drogerie|tankstelle|store|shop)"#)
    private static func p(_ pattern: String, _ cat: String, ambiguous: Bool = false) -> (NSRegularExpression, String, Bool) {
        (JSRegex.make(pattern), cat, ambiguous)
    }
    private static let prior: [(NSRegularExpression, String, Bool)] = [
        // groceries & drugstores
        p(#"\b(rewe|edeka|aldi|lidl|netto|kaufland|globus|tegut|denns|alnatura|marktkauf|famila|nahkauf|trinkgut|combi|hit markt|wasgau|feneberg|nahversorger)\b"#, "groceries"),
        p(#"\b(norma|penny|douglas)\b"#, "groceries", ambiguous: true),
        p(#"\b(rossmann|dm[- ]?drogerie|drogerie ?m[uü]ller|budni)\b"#, "groceries"),
        p(#"\b(bio ?company|basic bio|frischemarkt|getr[aä]nkemarkt|metro\b)\b"#, "groceries"),
        // dining, bakeries, delivery
        p(#"\b(mcdonald|burger king|kfc|subway|starbucks|dunkin|vapiano|nordsee|yormas|backwerk|kamps|b[aä]cker|baecker|dean ?& ?david|hans im gl[uü]ck|l'?osteria|five guys|pizza|d[oö]ner|doener|imbiss|restaurant|bistro|caf[eé]\b|kantine|mensa|trattoria|sushi|asia|steakhouse)\b"#, "dining"),
        p(#"\b(lieferando|uber ?eats|wolt|flink|gorillas|deliveroo|too good to go|foodora|knuspr)\b"#, "dining"),
        // subscriptions, media, phone & internet
        p(#"\b(netflix|spotify|disney|dazn|sky ?(deutschland|de)?\b|youtube ?premium|amazon prime|prime video|apple\.com\/bill|itunes|icloud|google ?(one|play|storage)|adobe|microsoft|office ?365|dropbox|notion|audible|patreon|nytimes|spiegel|zeit online|blinkist|duolingo|chatgpt|openai|anthropic)\b"#, "subscr"),
        p(#"\b(telekom|vodafone|o2\b|congstar|drillisch|sim24|simyo|winsim|freenet|1&1|1und1|aldi talk|lebara|lycamobile|blau\.de|pyur|unitymedia|1u1)\b"#, "subscr"),
        // transport, fuel, parking
        p(#"\b(deutsche bahn|db vertrieb|db fernverkehr|bahn\.de|bvg|mvg|hvv|rmv|vgn|vrr|vrs|vbb|flixbus|flixtrain|blablacar|uber(?! ?eats)|free ?now|lime\b|voi\b|nextbike|call a bike|swapfiets|sixt|europcar|hertz|miles mobility|share ?now)\b"#, "transport"),
        p(#"\b(bolt|tier|bird)\b"#, "transport", ambiguous: true),
        p(#"\b(aral|shell|esso|total ?energies|agip|omv|star tankstelle|tankstelle|hem tankstelle|raiffeisen tank)\b"#, "transport"),
        p(#"\b(apcoa|contipark|q-?park|easypark|parkster|parkhaus|parkraum)\b"#, "transport"),
        // shopping & home
        p(#"\b(amazon(?!.*prime)|zalando|about ?you|otto ?gmbh|media ?markt|mediamarkt|saturn|ikea|h ?& ?m|zara|c ?& ?a|primark|decathlon|thalia|conrad|action\b|tk ?maxx|depot\b|xxxlutz|h[oö]ffner|obi\b|bauhaus|hornbach|toom|globetrotter|snipes|foot ?locker|zooplus|fressnapf|temu|shein|aliexpress)\b"#, "shopping"),
        // health & fitness
        p(#"\b(apotheke|pharmacy|doctolib|zahnarzt|hausarzt|arztpraxis|klinik|krankenhaus|physio|labor\b)\b"#, "health"),
        p(#"\b(mcfit|fitx|clever ?fit|urban sports|fitness ?first|john reed|gold'?s gym|holmes place|superfit)\b"#, "health"),
        p(#"\b(techniker krankenkasse|\btk[- ]?buchnr|\baok\b|barmer|dak\b|\bikk\b|\bhkk\b|\bkkh\b|krankenkasse|\bbkk\b|debeka|pflegeversicherung)\b"#, "health"),
        // entertainment
        p(#"\b(kino|cinema|cinemaxx|uci ?kinowelt|cinestar|steam ?games|steampowered|playstation|xbox|nintendo|epic ?games|twitch|ticketmaster|eventim|museum|zoo\b|therme|freizeitbad|escape ?room|bowling)\b"#, "entertain"),
        // rent, utilities & bills
        p(#"\b(stadtwerke|vattenfall|e\.?on\b|enbw|rwe\b|gasag|lichtblick|naturstrom|yello ?strom|eprimo|octopus energy|energieversorgung|wasserwerk)\b"#, "rent"),
        p(#"\b(gez\b|rundfunk|beitragsservice|hausverwaltung|kaltmiete|warmmiete|nebenkosten|betriebskosten|vonovia|deutsche wohnen|lebensraum|wohnungsbau|mietkaution)\b"#, "rent"),
        p(#"\b(allianz|huk|\baxa\b|ergo ?versicherung|generali|signal iduna|cosmosdirekt|haftpflicht|hausrat|versicherung)\b"#, "rent"),
    ]

    /// A category id for a shop name, or nil when nothing is confident.
    static func category(_ name: String) -> String? {
        let n = name.trimmed
        if n.isEmpty { return nil }
        let looksRetail = n.split(whereSeparator: \.isWhitespace).count == 1 || JSRegex.test(retailCtx, n)
        for (re, cat, ambiguous) in prior {
            if !JSRegex.test(re, n) { continue }
            if ambiguous && !looksRetail { continue }   // "Norma Mueller" is a person, not a supermarket
            return cat
        }
        return nil
    }
}
